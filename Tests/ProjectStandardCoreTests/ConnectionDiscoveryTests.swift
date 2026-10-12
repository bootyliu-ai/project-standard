import Foundation
import Testing
@testable import ProjectStandardCore

private final class SnapshotCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var value: CodexConnectionSnapshot?

    func store(_ snapshot: CodexConnectionSnapshot?) {
        lock.lock()
        value = snapshot
        lock.unlock()
    }

    func load() -> CodexConnectionSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Suite("Connection discovery and capability probes")
struct ConnectionDiscoveryTests {
    @Test("verified capability matrix rejects missing protocol surfaces")
    func capabilityMatrix() {
        let verified = ClientCapabilityMatrix.assess(
            client: .codex,
            version: ClientCapabilityMatrix.verifiedCodexVersion,
            surfaces: ClientProbeSurfaces(accountStatus: true, appServer: true, projectRules: true)
        )
        #expect(verified.verification == .verified)
        #expect(verified.supportedCategories.count == 7)

        let bundled = ClientCapabilityMatrix.assess(
            client: .codex,
            version: ClientCapabilityMatrix.verifiedBundledCodexVersion,
            surfaces: ClientProbeSurfaces(accountStatus: true, appServer: true, projectRules: true)
        )
        #expect(bundled.verification == .verified)

        let missing = ClientCapabilityMatrix.assess(
            client: .codex,
            version: ClientCapabilityMatrix.verifiedCodexVersion,
            surfaces: ClientProbeSurfaces(accountStatus: true, appServer: false, projectRules: true)
        )
        #expect(missing.verification == .unavailable)
        #expect(missing.supportedCategories.isEmpty)

        let smartWork = ClientCapabilityMatrix.assess(
            client: .smartWork,
            version: ClientCapabilityMatrix.verifiedSmartWorkVersion,
            surfaces: ClientProbeSurfaces(
                accountStatus: false,
                projectRules: true,
                projectSkills: true
            )
        )
        #expect(smartWork.verification == .verified)
        #expect(smartWork.supportedCategories == [.prompt, .rules, .memory, .requirements, .skills])

        let dcc = ClientCapabilityMatrix.assess(
            client: .dcc,
            version: ClientCapabilityMatrix.verifiedDCCVersion,
            surfaces: ClientProbeSurfaces(
                accountStatus: false,
                projectRules: true,
                projectSkills: true
            )
        )
        #expect(dcc.verification == .verified)
        #expect(dcc.supportedCategories.count == 5)
    }

    @Test("DCC managed launcher is detected from an authorized local bin directory")
    func dccDetection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-standard-dcc-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("share/dcc/versions/1.7.24/dcc")
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data("dcc".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try FileManager.default.createSymbolicLink(
            at: bin.appendingPathComponent("dcc"),
            withDestinationURL: executable
        )

        let detector = ConnectionDetector(
            environment: ["PATH": ""],
            smartWorkApplicationURLs: [],
            additionalExecutableDirectories: [bin]
        )
        let profile = try #require(detector.discover().first { $0.client == .dcc })
        #expect(profile.id == "dcc-claude-local")
        #expect(profile.capabilities.version == "1.7.24")
        #expect(profile.capabilities.verification == .verified)
        #expect(profile.capabilities.supportedCategories.count == 5)
    }

    @Test("Claude Code is detected from an authorized local bin directory")
    func claudeCodeDetection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-standard-claude-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("claude")
        let script = #"""
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo "2.1.212 (Claude Code)"; exit 0; fi
        if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
          echo '{"loggedIn":true,"authMethod":"oauth","apiProvider":"anthropic"}'
          exit 0
        fi
        exit 1
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let detector = ConnectionDetector(
            environment: ["PATH": ""],
            smartWorkApplicationURLs: [],
            additionalExecutableDirectories: [root]
        )
        let profile = try #require(detector.discover().first { $0.client == .claudeCode })
        #expect(profile.title == "Claude Code · Anthropic")
        #expect(profile.capabilities.verification == .verified)
        #expect(profile.capabilities.supportedCategories.count == 7)
    }

    @Test("Smart Work app bundle is detected without reading user credentials")
    func smartWorkBundleDetection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-standard-smartwork-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("SmartWork.app/Contents", isDirectory: true)
        let runtime = contents.appendingPathComponent("Resources/server/bin/smartwork-agent-runtime.mjs")
        try FileManager.default.createDirectory(at: runtime.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("runtime".utf8).write(to: runtime)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
        try Data("bundle".utf8).write(to: contents.appendingPathComponent("Resources/app.asar"))
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.dichat.smartwork",
            "CFBundleShortVersionString": ClientCapabilityMatrix.verifiedSmartWorkVersion
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        let app = contents.deletingLastPathComponent()
        let detector = ConnectionDetector(environment: ["PATH": ""], smartWorkApplicationURLs: [app])
        let profile = try #require(detector.discover().first { $0.client == .smartWork })
        #expect(profile.id == "smartwork-local")
        #expect(profile.title == "Smart Work · 本机应用")
        #expect(profile.capabilities.verification == .verified)
        #expect(profile.capabilities.supportedCategories.count == 5)
    }

    @Test("App Server state ignores identity fields and keeps routing metadata")
    func appServerReducer() throws {
        var reducer = CodexAppServerStateReducer()
        reducer.consumeAccount([
            "requiresOpenaiAuth": true,
            "account": [
                "type": "chatgpt",
                "planType": "plus",
                "email": "must-not-enter-the-model@example.invalid"
            ]
        ])
        reducer.consumeConfig(["config": ["model_provider": "company-llm"]])
        let snapshot = try #require(reducer.snapshot)
        #expect(snapshot.authMode == "chatgpt")
        #expect(snapshot.planType == "plus")
        #expect(snapshot.modelProvider == "company-llm")
    }

    @Test("custom Codex provider becomes a distinct connection profile")
    func customProviderProfile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-standard-probe-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("codex")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo "codex-cli 0.146.0"; exit 0; fi
        if [ "$1" = "app-server" ] || [ "$1" = "execpolicy" ]; then exit 0; fi
        exit 1
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let detector = ConnectionDetector(environment: ["PATH": root.path])
        let profiles = detector.discover(codexSnapshot: CodexConnectionSnapshot(
            authMode: nil,
            planType: nil,
            modelProvider: "company-llm",
            requiresOpenAIAuth: false
        ))
        let profile = try #require(profiles.first { $0.client == .codex })
        #expect(profile.id == "codex-company-llm-external-local")
        #expect(profile.title == "Codex · Company Llm")
        #expect(profile.configSource == "Codex App Server")
        #expect(profile.capabilities.verification == .verified)
    }

    @Test("App Server config events refresh the active provider")
    func appServerConfigEvent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-standard-app-server-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("fake-codex")
        let script = #"""
        #!/bin/sh
        account_count=0
        config_count=0
        while IFS= read -r line; do
          case "$line" in
            *initialize*) echo '{"id":1,"result":{}}' ;;
            *account*read*)
              account_count=$((account_count + 1))
              if [ "$account_count" -eq 1 ]; then id=2; else id=5; fi
              echo "{\"id\":$id,\"result\":{\"account\":{\"type\":\"chatgpt\",\"planType\":\"plus\"},\"requiresOpenaiAuth\":true}}"
              ;;
            *config*read*)
              config_count=$((config_count + 1))
              if [ "$config_count" -eq 1 ]; then
                echo '{"id":3,"result":{"config":{"model_provider":"openai"},"origins":{}}}'
              else
                echo '{"id":6,"result":{"config":{"model_provider":"company-llm"},"origins":{}}}'
              fi
              ;;
            *fs*watch*)
              echo '{"id":4,"result":{"path":"/tmp"}}'
              echo '{"method":"fs/changed","params":{"watchId":"project-standard-codex-home","changedPaths":["/tmp/config.toml"]}}'
              ;;
          esac
        done
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let capture = SnapshotCapture()
        let completed = DispatchSemaphore(value: 0)
        let monitor = try CodexAppServerMonitor(
            executableURL: executable,
            cwdURL: root,
            codexHomeURL: root
        ) { snapshot in
            capture.store(snapshot)
            if snapshot?.modelProvider == "company-llm" { completed.signal() }
        }
        defer { monitor.stop() }
        #expect(completed.wait(timeout: .now() + 5) == .success)
        #expect(capture.load()?.modelProvider == "company-llm")
    }
}
