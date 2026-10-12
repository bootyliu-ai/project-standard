import Foundation

public struct ConnectionDetector {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let preferBundledCodex: Bool
    private let smartWorkApplicationURLs: [URL]
    private let additionalExecutableDirectories: [URL]
    private let customClients: [CustomClientDefinition]

    public init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferBundledCodex: Bool = false,
        smartWorkApplicationURLs: [URL]? = nil,
        additionalExecutableDirectories: [URL] = [],
        customClients: [CustomClientDefinition] = []
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.preferBundledCodex = preferBundledCodex
        self.smartWorkApplicationURLs = smartWorkApplicationURLs ?? [
            URL(fileURLWithPath: "/Applications/SmartWork.app", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/SmartWork.app", isDirectory: true)
        ]
        self.additionalExecutableDirectories = additionalExecutableDirectories
        self.customClients = customClients
    }

    public func discover(codexSnapshot: CodexConnectionSnapshot? = nil) -> [ConnectionProfile] {
        var profiles: [ConnectionProfile] = []
        if let executable = executableURL(for: .codex) {
            profiles.append(codexProfile(executable: executable, snapshot: codexSnapshot))
        }
        if let executable = executableURL(for: .claudeCode) {
            profiles.append(claudeProfile(executable: executable))
        }
        if let executable = executableURL(for: .dcc) {
            profiles.append(dccProfile(executable: executable))
        }
        if let application = smartWorkApplicationURL() {
            profiles.append(smartWorkProfile(application: application))
        }
        profiles.append(contentsOf: customClients.map(customClientProfile))
        return profiles
    }

    public func executableURL(for client: ClientKind) -> URL? {
        let executable: String
        let bundledExecutablePaths: [String]
        switch client {
        case .codex:
            executable = "codex"
            bundledExecutablePaths = [
                "/Applications/Codex.app/Contents/Resources/codex",
                "/Applications/ChatGPT.app/Contents/Resources/codex"
            ]
        case .claudeCode:
            executable = "claude"
            bundledExecutablePaths = []
        case .smartWork:
            return smartWorkApplicationURL().flatMap { smartWorkRuntimeURL(application: $0) }
        case .dcc:
            executable = "dcc"
            bundledExecutablePaths = []
        case .custom:
            return nil
        }
        let knownPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        ]
        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        if client == .codex, preferBundledCodex,
           let bundled = bundledExecutablePaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: bundled)
        }
        var searched = Set<String>()
        let additionalPaths = additionalExecutableDirectories.map(\.path)
        for directory in pathDirectories + additionalPaths + knownPaths where searched.insert(directory).inserted {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(executable)
            if fileManager.isExecutableFile(atPath: url.path) { return url }
        }
        if let bundled = bundledExecutablePaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: bundled)
        }
        return nil
    }

    private func customClientProfile(_ definition: CustomClientDefinition) -> ConnectionProfile {
        let capability = ClientCapabilityMatrix.assess(
            client: .custom,
            version: "custom",
            surfaces: ClientProbeSurfaces(accountStatus: false, projectRules: true, projectSkills: true)
        )
        return ConnectionProfile(
            id: definition.profileID,
            client: .custom,
            title: definition.name,
            detail: "自定义端 · 5/7 可用",
            configSource: "\(definition.instructionFile) · \(definition.skillsDirectory)",
            confidence: .confirmed,
            capabilities: capability,
            customDefinition: definition
        )
    }

    private func smartWorkApplicationURL() -> URL? {
        smartWorkApplicationURLs.first { application in
            guard fileManager.fileExists(atPath: application.path),
                  let info = smartWorkInfo(application: application) else { return false }
            return info.bundleIdentifier == "com.dichat.smartwork"
        }
    }

    private func smartWorkRuntimeURL(application: URL) -> URL? {
        let candidates = [
            application.appendingPathComponent("Contents/Resources/server/bin/smartwork-agent-runtime.mjs"),
            application.appendingPathComponent("Contents/Resources/src-tauri/codex-aarch64-apple-darwin")
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func smartWorkProfile(application: URL) -> ConnectionProfile {
        let info = smartWorkInfo(application: application)
        let version = info?.version
        let hasRuntime = smartWorkRuntimeURL(application: application) != nil
        let hasApplicationSource = fileManager.fileExists(
            atPath: application.appendingPathComponent("Contents/Resources/app.asar").path
        )
        let capability = ClientCapabilityMatrix.assess(
            client: .smartWork,
            version: version,
            surfaces: ClientProbeSurfaces(
                accountStatus: false,
                projectRules: hasRuntime && hasApplicationSource,
                projectSkills: hasRuntime && hasApplicationSource
            )
        )
        return ConnectionProfile(
            id: "smartwork-local",
            client: .smartWork,
            title: "Smart Work · 本机应用",
            detail: "项目规则与 Skills · \(capability.detail)",
            configSource: application.path,
            confidence: capability.verification == .unavailable ? .unknown : .confirmed,
            capabilities: capability
        )
    }

    private func smartWorkInfo(application: URL) -> (bundleIdentifier: String, version: String?)? {
        let infoURL = application.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleIdentifier = root["CFBundleIdentifier"] as? String else { return nil }
        return (bundleIdentifier, root["CFBundleShortVersionString"] as? String)
    }

    private func dccProfile(executable: URL) -> ConnectionProfile {
        let version = managedExecutableVersion(executable)
        let capability = ClientCapabilityMatrix.assess(
            client: .dcc,
            version: version,
            surfaces: ClientProbeSurfaces(
                accountStatus: false,
                projectRules: true,
                projectSkills: true
            )
        )
        return ConnectionProfile(
            id: "dcc-claude-local",
            client: .dcc,
            title: "DCC · 本地 Claude Code",
            detail: "DiDi CLI 封装 · \(capability.detail)",
            configSource: executable.path,
            confidence: .confirmed,
            capabilities: capability
        )
    }

    private func managedExecutableVersion(_ executable: URL) -> String? {
        let resolved = executable.resolvingSymlinksInPath()
        let components = resolved.pathComponents
        guard let versionsIndex = components.lastIndex(of: "versions"),
              components.indices.contains(versionsIndex + 1) else { return nil }
        return semanticVersion(components[versionsIndex + 1])
    }

    private func codexProfile(executable: URL, snapshot: CodexConnectionSnapshot?) -> ConnectionProfile {
        let version = semanticVersion(run(executable, arguments: ["--version"]))
        let appServer = commandSucceeds(executable, arguments: ["app-server", "--help"])
        let rules = commandSucceeds(executable, arguments: ["execpolicy", "--help"])
        let fallbackStatus = snapshot == nil ? run(executable, arguments: ["login", "status"]).lowercased() : ""
        let capability = ClientCapabilityMatrix.assess(
            client: .codex,
            version: version,
            surfaces: ClientProbeSurfaces(
                accountStatus: snapshot != nil || !fallbackStatus.isEmpty,
                appServer: appServer,
                projectRules: rules
            )
        )

        if let snapshot {
            return codexAppServerProfile(snapshot: snapshot, capability: capability)
        }
        if fallbackStatus.contains("chatgpt") {
            return ConnectionProfile(
                id: "codex-chatgpt-openai-local",
                client: .codex,
                title: "Codex · ChatGPT 登录",
                detail: "官方账号 · \(capability.detail)",
                configSource: "Codex CLI fallback",
                confidence: .confirmed,
                capabilities: capability
            )
        }
        if fallbackStatus.contains("api key") || fallbackStatus.contains("api-key") {
            return ConnectionProfile(
                id: "codex-apikey-openai-local",
                client: .codex,
                title: "Codex · OpenAI API Key",
                detail: "API 接入 · \(capability.detail)",
                configSource: "Codex CLI fallback",
                confidence: .confirmed,
                capabilities: capability
            )
        }
        return ConnectionProfile(
            id: "codex-current-local",
            client: .codex,
            title: "Codex · 当前配置",
            detail: "认证 / Provider 待识别 · \(capability.detail)",
            configSource: "客户端当前配置",
            confidence: .unknown,
            capabilities: capability
        )
    }

    private func codexAppServerProfile(
        snapshot: CodexConnectionSnapshot,
        capability: ClientCapabilityReport
    ) -> ConnectionProfile {
        let provider = normalizedProvider(snapshot.modelProvider, accountType: snapshot.authMode)
        let providerLabel = displayProvider(provider)
        let auth = normalizedAuth(snapshot.authMode, requiresOpenAIAuth: snapshot.requiresOpenAIAuth)
        let authLabel: String
        switch auth {
        case "chatgpt": authLabel = snapshot.planType.map { "ChatGPT \(displayPlan($0))" } ?? "ChatGPT 登录"
        case "apikey": authLabel = "API Key"
        case "bedrock": authLabel = "Bedrock 凭据"
        case "external": authLabel = "外部 Provider"
        default: authLabel = "认证待识别"
        }
        let title = provider == "openai"
            ? (auth == "chatgpt" ? "Codex · ChatGPT 登录" : "Codex · OpenAI \(authLabel)")
            : "Codex · \(providerLabel)"
        return ConnectionProfile(
            id: "codex-\(safeIdentifier(provider))-\(safeIdentifier(auth))-local",
            client: .codex,
            title: title,
            detail: "\(authLabel) · \(capability.detail)",
            configSource: "Codex App Server",
            confidence: provider == "unknown" || auth == "unknown" ? .unknown : .confirmed,
            capabilities: capability
        )
    }

    private func claudeProfile(executable: URL) -> ConnectionProfile {
        let version = managedExecutableVersion(executable) ?? semanticVersion(run(executable, arguments: ["--version"]))
        guard let data = runData(executable, arguments: ["auth", "status", "--json"]),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["loggedIn"] as? Bool == true else {
            let capability = ClientCapabilityMatrix.assess(
                client: .claudeCode,
                version: version,
                surfaces: ClientProbeSurfaces(accountStatus: version != nil)
            )
            return ConnectionProfile(
                id: "claude-current-local",
                client: .claudeCode,
                title: "Claude Code · 当前配置",
                detail: "认证 / Provider 待识别 · \(capability.detail)",
                configSource: "客户端当前配置",
                confidence: .unknown,
                capabilities: capability
            )
        }
        let capability = ClientCapabilityMatrix.assess(
            client: .claudeCode,
            version: version,
            surfaces: ClientProbeSurfaces(accountStatus: true)
        )
        let method = root["authMethod"] as? String ?? "unknown"
        let provider = root["apiProvider"] as? String ?? "unknown"
        let providerLabel = switch provider.lowercased() {
        case "firstparty", "anthropic": "Anthropic"
        case "bedrock": "Amazon Bedrock"
        case "vertex", "vertexai": "Google Vertex AI"
        default: provider
        }
        let authLabel = method.lowercased().contains("oauth") ? "订阅登录" : "API Key"
        return ConnectionProfile(
            id: "claude-\(safeIdentifier(provider))-\(safeIdentifier(method))-local",
            client: .claudeCode,
            title: "Claude Code · \(providerLabel)",
            detail: "\(authLabel) · \(capability.detail)",
            configSource: "claude auth status",
            confidence: .confirmed,
            capabilities: capability
        )
    }

    private func normalizedProvider(_ value: String?, accountType: String?) -> String {
        if let value, !value.isEmpty { return value.lowercased() }
        if accountType == "amazonBedrock" || accountType == "bedrockApiKey" { return "amazon-bedrock" }
        if accountType != nil { return "openai" }
        return "unknown"
    }

    private func normalizedAuth(_ value: String?, requiresOpenAIAuth: Bool?) -> String {
        switch value?.lowercased() {
        case "chatgpt", "chatgptauthtokens": return "chatgpt"
        case "apikey": return "apikey"
        case "amazonbedrock", "bedrockapikey": return "bedrock"
        case "headers", "agentidentity", "personalaccesstoken": return "external"
        case .none where requiresOpenAIAuth == false: return "external"
        default: return "unknown"
        }
    }

    private func displayProvider(_ value: String) -> String {
        switch value.lowercased() {
        case "openai": "OpenAI"
        case "amazon-bedrock", "bedrock": "Amazon Bedrock"
        default: value.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        }
    }

    private func displayPlan(_ value: String) -> String {
        switch value.lowercased() {
        case "plus": "Plus"
        case "pro": "Pro"
        case "team", "business", "self_serve_business_usage_based": "Business"
        case "enterprise", "enterprise_cbp_usage_based", "ent26": "Enterprise"
        case "edu": "Edu"
        default: value.capitalized
        }
    }

    private func commandSucceeds(_ executable: URL, arguments: [String]) -> Bool {
        runData(executable, arguments: arguments) != nil
    }

    private func semanticVersion(_ output: String) -> String? {
        output.split(whereSeparator: { $0.isWhitespace }).map(String.init).first { token in
            let clean = token.trimmingCharacters(in: CharacterSet(charactersIn: "v,()"))
            let numeric = clean.split(separator: "-", maxSplits: 1).first ?? ""
            let parts = numeric.split(separator: ".")
            return parts.count >= 2 && parts.allSatisfy { Int($0) != nil }
        }.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "v,()")) }
    }

    private func run(_ executable: URL, arguments: [String]) -> String {
        guard let data = runData(executable, arguments: arguments) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private func runData(_ executable: URL, arguments: [String]) -> Data? {
        guard executable.isFileURL, executable.path.hasPrefix("/") else { return nil }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    private func safeIdentifier(_ value: String) -> String {
        value.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { $0.append($1) }
    }
}
