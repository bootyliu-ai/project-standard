import Foundation

public struct ProjectManifest: Codable, Sendable {
    public let schemaVersion: Int
    public let projectId: String
    public let schemes: [ManifestScheme]

    public init(schemaVersion: Int, projectId: String, schemes: [ManifestScheme]) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.schemes = schemes
    }
}

public struct ManifestScheme: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let sources: SchemeSources?

    public init(id: String, name: String, sources: SchemeSources? = nil) {
        self.id = id
        self.name = name
        self.sources = sources
    }
}

public struct SchemeSources: Codable, Sendable {
    public let prompt: String
    public let rules: String
    public let memory: String
    public let requirements: String
    public let skills: String
    public let toolsMcp: String
    public let permissionsHooks: String

    public init(
        prompt: String,
        rules: String,
        memory: String,
        requirements: String,
        skills: String,
        toolsMcp: String,
        permissionsHooks: String
    ) {
        self.prompt = prompt
        self.rules = rules
        self.memory = memory
        self.requirements = requirements
        self.skills = skills
        self.toolsMcp = toolsMcp
        self.permissionsHooks = permissionsHooks
    }
}

public enum FoundationCategory: String, CaseIterable, Codable, Sendable {
    case prompt
    case rules
    case memory
    case requirements
    case skills
    case toolsMcp
    case permissionsHooks

    public var displayName: String {
        switch self {
        case .prompt: "基础 Prompt"
        case .rules: "规范与 Rules"
        case .memory: "记忆"
        case .requirements: "项目要求"
        case .skills: "Skills"
        case .toolsMcp: "Tools 与 MCP"
        case .permissionsHooks: "权限与 Hooks"
        }
    }

    public var defaultFileName: String {
        switch self {
        case .prompt: "prompt.md"
        case .rules: "rules.md"
        case .memory: "memory.md"
        case .requirements: "requirements.md"
        case .skills: "skills"
        case .toolsMcp: "tools-mcp.json"
        case .permissionsHooks: "permissions-hooks.json"
        }
    }
}

public struct CategorySource: Identifiable, Sendable {
    public var id: FoundationCategory { category }
    public let category: FoundationCategory
    public let relativePath: String
    public let url: URL
    public let itemCount: Int
    public let exists: Bool

    public init(
        category: FoundationCategory,
        relativePath: String,
        url: URL,
        itemCount: Int,
        exists: Bool
    ) {
        self.category = category
        self.relativePath = relativePath
        self.url = url
        self.itemCount = itemCount
        self.exists = exists
    }
}

public struct Scheme: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let categories: [CategorySource]

    public init(id: String, name: String, categories: [CategorySource]) {
        self.id = id
        self.name = name
        self.categories = categories
    }

    public var itemCount: Int { categories.reduce(0) { $0 + $1.itemCount } }
    public var existingCategoryCount: Int { categories.filter(\.exists).count }
}

public struct LoadedProject: Sendable {
    public let rootURL: URL
    public let manifest: ProjectManifest
    public let schemes: [Scheme]

    public init(rootURL: URL, manifest: ProjectManifest, schemes: [Scheme]) {
        self.rootURL = rootURL
        self.manifest = manifest
        self.schemes = schemes
    }

    public var displayName: String { rootURL.lastPathComponent }
}

public enum ClientKind: String, Codable, Sendable, CaseIterable {
    case codex
    case claudeCode
    case smartWork
    case dcc
    case custom

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .smartWork: "Smart Work"
        case .dcc: "DCC"
        case .custom: "自定义端"
        }
    }

    public var iconText: String {
        switch self {
        case .codex: "CX"
        case .claudeCode: "CL"
        case .smartWork: "SW"
        case .dcc: "DC"
        case .custom: "AG"
        }
    }
}

public enum CustomClientDefinitionError: LocalizedError {
    case emptyName
    case invalidRelativePath(String)
    case reservedPath(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName: "请输入端名称"
        case .invalidRelativePath(let path): "必须填写项目内的相对路径：\(path)"
        case .reservedPath(let path): "不能把投影写入项目规范源目录：\(path)"
        }
    }
}

/// A user-defined project adapter. It deliberately describes only project-local
/// surfaces that can be validated without reading credentials or invoking the agent.
public struct CustomClientDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var instructionFile: String
    public var skillsDirectory: String

    public init(id: String, name: String, instructionFile: String, skillsDirectory: String) throws {
        let allowedID = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !id.isEmpty, id.unicodeScalars.allSatisfy(allowedID.contains) else {
            throw CustomClientDefinitionError.invalidRelativePath("端标识")
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw CustomClientDefinitionError.emptyName }
        self.id = id
        self.name = cleanName
        self.instructionFile = try Self.validatedRelativePath(instructionFile)
        self.skillsDirectory = try Self.validatedRelativePath(skillsDirectory)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, instructionFile, skillsDirectory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            instructionFile: container.decode(String.self, forKey: .instructionFile),
            skillsDirectory: container.decode(String.self, forKey: .skillsDirectory)
        )
    }

    public var profileID: String { "custom-\(id)" }
    public var markerIdentifier: String { "custom-\(id)" }

    private static func validatedRelativePath(_ value: String) throws -> String {
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"),
              !components.contains(""), !components.contains("."), !components.contains("..") else {
            throw CustomClientDefinitionError.invalidRelativePath(path.isEmpty ? "未填写" : path)
        }
        guard components.first != ".project-standard" else {
            throw CustomClientDefinitionError.reservedPath(path)
        }
        return components.joined(separator: "/")
    }
}

public struct ProjectionDestination: Sendable, Equatable {
    public let client: ClientKind
    public let markerIdentifier: String
    public let instructionFile: String
    public let skillsDirectory: String

    public init(client: ClientKind) {
        self.client = client
        self.markerIdentifier = client.rawValue
        self.instructionFile = client == .claudeCode || client == .dcc ? "CLAUDE.md" : "AGENTS.md"
        self.skillsDirectory = client == .claudeCode || client == .dcc ? ".claude/skills" : ".agents/skills"
    }

    public init(custom definition: CustomClientDefinition) {
        self.client = .custom
        self.markerIdentifier = definition.markerIdentifier
        self.instructionFile = definition.instructionFile
        self.skillsDirectory = definition.skillsDirectory
    }
}

public enum DetectionConfidence: String, Codable, Sendable {
    case confirmed
    case inferred
    case unknown
}

public enum CapabilityVerification: String, Codable, Sendable {
    case verified
    case compatible
    case unverified
    case unavailable
}

public struct ClientCapabilityReport: Codable, Sendable, Equatable {
    public let version: String?
    public let verification: CapabilityVerification
    public let detail: String
    public let supportedCategories: Set<FoundationCategory>

    public init(
        version: String?,
        verification: CapabilityVerification,
        detail: String,
        supportedCategories: Set<FoundationCategory>
    ) {
        self.version = version
        self.verification = verification
        self.detail = detail
        self.supportedCategories = supportedCategories
    }
}

/// Non-secret account and routing metadata returned by Codex App Server.
/// Email and credential fields are deliberately absent from this model.
public struct CodexConnectionSnapshot: Sendable, Equatable {
    public let authMode: String?
    public let planType: String?
    public let modelProvider: String?
    public let requiresOpenAIAuth: Bool?

    public init(
        authMode: String?,
        planType: String?,
        modelProvider: String?,
        requiresOpenAIAuth: Bool?
    ) {
        self.authMode = authMode
        self.planType = planType
        self.modelProvider = modelProvider
        self.requiresOpenAIAuth = requiresOpenAIAuth
    }
}

public struct ConnectionProfile: Identifiable, Codable, Sendable {
    public let id: String
    public let client: ClientKind
    public let title: String
    public let detail: String
    public let configSource: String
    public let confidence: DetectionConfidence
    public let capabilities: ClientCapabilityReport
    public let customDefinition: CustomClientDefinition?

    public init(
        id: String,
        client: ClientKind,
        title: String,
        detail: String,
        configSource: String,
        confidence: DetectionConfidence,
        capabilities: ClientCapabilityReport,
        customDefinition: CustomClientDefinition? = nil
    ) {
        self.id = id
        self.client = client
        self.title = title
        self.detail = detail
        self.configSource = configSource
        self.confidence = confidence
        self.capabilities = capabilities
        self.customDefinition = customDefinition
    }

    public var projectionDestination: ProjectionDestination {
        customDefinition.map(ProjectionDestination.init(custom:)) ?? ProjectionDestination(client: client)
    }
}

public struct BindingRecord: Codable, Sendable {
    public let projectID: String
    public let profileID: String
    public let client: ClientKind
    public var schemeID: String
    public var validatedCategories: Int
    public var updatedAt: Date

    public init(
        projectID: String,
        profileID: String,
        client: ClientKind,
        schemeID: String,
        validatedCategories: Int,
        updatedAt: Date = Date()
    ) {
        self.projectID = projectID
        self.profileID = profileID
        self.client = client
        self.schemeID = schemeID
        self.validatedCategories = validatedCategories
        self.updatedAt = updatedAt
    }
}
