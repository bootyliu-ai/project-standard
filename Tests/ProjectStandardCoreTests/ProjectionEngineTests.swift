import Foundation
import Testing
@testable import ProjectStandardCore

@Suite("Seven-category projection")
struct ProjectionEngineTests {
    private enum InjectedFailure: Error { case expected }

    @Test("Claude projection merges all categories and cancellation preserves user JSON")
    func claudeLifecycle() throws {
        let root = try configuredFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try Data(#"{"theme":"dark","permissions":{"allow":["Read"]}}"#.utf8)
            .write(to: root.appendingPathComponent(".claude/settings.json"))
        try Data(#"{"mcpServers":{"user-server":{"command":"user"}},"other":true}"#.utf8)
            .write(to: root.appendingPathComponent(".mcp.json"))

        let project = try ProjectLoader().load(rootURL: root)
        let scheme = try #require(project.schemes.first)
        let engine = ProjectionEngine()

        let first = try engine.apply(project: project, scheme: scheme, client: .claudeCode)
        #expect(first.count == 7)
        let settingsAfterFirst = try Data(contentsOf: root.appendingPathComponent(".claude/settings.json"))
        _ = try engine.apply(project: project, scheme: scheme, client: .claudeCode)
        #expect(try Data(contentsOf: root.appendingPathComponent(".claude/settings.json")) == settingsAfterFirst)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".claude/skills/project-standard-base-review/SKILL.md").path))

        try engine.cancel(project: project, scheme: scheme, client: .claudeCode)
        let settings = try json(root.appendingPathComponent(".claude/settings.json"))
        #expect(settings["theme"] as? String == "dark")
        #expect((settings["permissions"] as? [String: Any])?["allow"] as? [String] == ["Read"])
        let mcp = try json(root.appendingPathComponent(".mcp.json"))
        #expect((mcp["mcpServers"] as? [String: Any])?["user-server"] != nil)
        #expect(mcp["other"] as? Bool == true)
        #expect(engine.validate(project: project, scheme: scheme, client: .claudeCode).count == 0)
    }

    @Test("Codex projection writes marked TOML and relative skill links")
    func codexLifecycle() throws {
        let root = try configuredFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try "model = \"user-choice\"\n".write(
            to: root.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )
        let project = try ProjectLoader().load(rootURL: root)
        let scheme = try #require(project.schemes.first)
        let engine = ProjectionEngine()

        let validation = try engine.apply(project: project, scheme: scheme, client: .codex)
        #expect(validation.count == 7)
        let config = try String(contentsOf: root.appendingPathComponent(".codex/config.toml"), encoding: .utf8)
        #expect(config.contains("model = \"user-choice\""))
        #expect(config.contains("[mcp_servers.\"project-standard.base.docs\"]"))
        #expect(config.contains("[[hooks.PreToolUse]]"))
        let rulesURL = root.appendingPathComponent(".codex/rules/project-standard.rules")
        let rules = try String(contentsOf: rulesURL, encoding: .utf8)
        #expect(rules.contains(#"pattern = ["git", "status"]"#))
        #expect(rules.contains(#"decision = "allow""#))

        try engine.cancel(project: project, scheme: scheme, client: .codex)
        #expect(try String(contentsOf: root.appendingPathComponent(".codex/config.toml"), encoding: .utf8) == "model = \"user-choice\"\n")
        #expect(!FileManager.default.fileExists(atPath: rulesURL.path))
        #expect(engine.validate(project: project, scheme: scheme, client: .codex).count == 0)
    }

    @Test("Smart Work projects verified rules and repository skills only")
    func smartWorkLifecycle() throws {
        let root = try configuredFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try ProjectLoader().load(rootURL: root)
        let scheme = try #require(project.schemes.first)
        let engine = ProjectionEngine()

        let validation = try engine.apply(project: project, scheme: scheme, client: .smartWork)
        #expect(validation.effective == [.prompt, .rules, .memory, .requirements, .skills])
        let agents = try String(contentsOf: root.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        #expect(agents.contains("client=smartWork"))
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".agents/skills/project-standard-smartwork-base-review/SKILL.md").path
        ))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".codex").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".mcp.json").path))

        try engine.cancel(project: project, scheme: scheme, client: .smartWork)
        #expect(engine.validate(project: project, scheme: scheme, client: .smartWork).count == 0)
    }

    @Test("DCC projects Claude-compatible rules and project skills")
    func dccLifecycle() throws {
        let root = try configuredFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try ProjectLoader().load(rootURL: root)
        let scheme = try #require(project.schemes.first)
        let engine = ProjectionEngine()

        let validation = try engine.apply(project: project, scheme: scheme, client: .dcc)
        #expect(validation.effective == [.prompt, .rules, .memory, .requirements, .skills])
        let instructions = try String(contentsOf: root.appendingPathComponent("CLAUDE.md"), encoding: .utf8)
        #expect(instructions.contains("client=dcc"))
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".claude/skills/project-standard-dcc-base-review/SKILL.md").path
        ))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".mcp.json").path))

        try engine.cancel(project: project, scheme: scheme, client: .dcc)
        #expect(engine.validate(project: project, scheme: scheme, client: .dcc).count == 0)
    }

    @Test("custom agents use independent project paths and ownership markers")
    func customAgentLifecycle() throws {
        let root = try configuredFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try ProjectLoader().load(rootURL: root)
        let scheme = try #require(project.schemes.first)
        let first = try CustomClientDefinition(
            id: "alpha",
            name: "Alpha Agent",
            instructionFile: "AI.md",
            skillsDirectory: ".alpha/skills"
        )
        let second = try CustomClientDefinition(
            id: "beta",
            name: "Beta Agent",
            instructionFile: "AI.md",
            skillsDirectory: ".alpha/skills"
        )
        let firstProfile = ConnectionDetector(
            environment: ["PATH": ""],
            smartWorkApplicationURLs: [],
            customClients: [first]
        ).discover().first { $0.client == .custom }!
        let secondProfile = ConnectionDetector(
            environment: ["PATH": ""],
            smartWorkApplicationURLs: [],
            customClients: [second]
        ).discover().first { $0.client == .custom }!
        let engine = ProjectionEngine()

        #expect(try engine.apply(project: project, scheme: scheme, profile: firstProfile).count == 5)
        #expect(try engine.apply(project: project, scheme: scheme, profile: secondProfile).count == 5)
        let instructions = try String(contentsOf: root.appendingPathComponent("AI.md"), encoding: .utf8)
        #expect(instructions.contains("client=custom-alpha"))
        #expect(instructions.contains("client=custom-beta"))

        try engine.cancel(project: project, scheme: scheme, profile: firstProfile)
        let afterCancel = try String(contentsOf: root.appendingPathComponent("AI.md"), encoding: .utf8)
        #expect(!afterCancel.contains("client=custom-alpha"))
        #expect(afterCancel.contains("client=custom-beta"))
        #expect(engine.validate(project: project, scheme: scheme, profile: secondProfile).count == 5)
    }

    @Test("custom agent paths cannot escape the project or overwrite canonical sources")
    func customAgentPathValidation() {
        #expect(throws: CustomClientDefinitionError.self) {
            try CustomClientDefinition(id: "bad", name: "Bad", instructionFile: "../AGENTS.md", skillsDirectory: ".agents/skills")
        }
        #expect(throws: CustomClientDefinitionError.self) {
            try CustomClientDefinition(id: "bad", name: "Bad", instructionFile: ".project-standard/prompt.md", skillsDirectory: ".agents/skills")
        }
    }

    @Test("failed multi-file apply restores every earlier mutation")
    func applyRollback() throws {
        let root = try configuredFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "# User-owned instructions\n"
        try original.write(to: root.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        let project = try ProjectLoader().load(rootURL: root)
        let scheme = try #require(project.schemes.first)
        let engine = ProjectionEngine { stage in
            if case .toolsMcp = stage { throw InjectedFailure.expected }
        }

        #expect(throws: InjectedFailure.self) {
            try engine.apply(project: project, scheme: scheme, client: .codex)
        }
        #expect(try String(contentsOf: root.appendingPathComponent("AGENTS.md"), encoding: .utf8) == original)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".agents").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".codex").path))
    }

    @Test("failed multi-file cancel restores the active projection")
    func cancelRollback() throws {
        let root = try configuredFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try ProjectLoader().load(rootURL: root)
        let scheme = try #require(project.schemes.first)
        _ = try ProjectionEngine().apply(project: project, scheme: scheme, client: .codex)
        let engine = ProjectionEngine { stage in
            if case .skills = stage { throw InjectedFailure.expected }
        }

        #expect(throws: InjectedFailure.self) {
            try engine.cancel(project: project, scheme: scheme, client: .codex)
        }
        #expect(engine.validate(project: project, scheme: scheme, client: .codex).count == 7)
    }

    private func configuredFixture() throws -> URL {
        let root = try FixtureProject.make(schemeIDs: ["base"])
        let scheme = root.appendingPathComponent(".project-standard/schemes/base")
        let skill = scheme.appendingPathComponent("skills/review")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "---\nname: review\ndescription: Review code.\n---\n\nReview changes.".write(
            to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        try Data(#"{"tools":[],"mcpServers":{"docs":{"type":"http","url":"https://example.invalid/mcp"}}}"#.utf8)
            .write(to: scheme.appendingPathComponent("tools-mcp.json"))
        try Data(#"{"permissions":{"allow":["Bash(git status)"]},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"./scripts/check.sh"}]}]}}"#.utf8)
            .write(to: scheme.appendingPathComponent("permissions-hooks.json"))
        return root
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
