import Foundation

public struct ClientProbeSurfaces: Sendable, Equatable {
    public let accountStatus: Bool
    public let appServer: Bool
    public let projectRules: Bool
    public let projectSkills: Bool

    public init(
        accountStatus: Bool,
        appServer: Bool = false,
        projectRules: Bool = false,
        projectSkills: Bool = false
    ) {
        self.accountStatus = accountStatus
        self.appServer = appServer
        self.projectRules = projectRules
        self.projectSkills = projectSkills
    }
}

/// The matrix is intentionally strict: only versions exercised by this repository's
/// regression suite are marked verified. New versions remain usable, but the UI makes
/// the need for re-verification visible instead of silently carrying an old claim.
public enum ClientCapabilityMatrix {
    public static let verifiedCodexVersion = "0.146.0"
    public static let verifiedBundledCodexVersion = "0.154.0-alpha.6.2"
    public static let verifiedClaudeVersion = "2.1.212"
    public static let verifiedSmartWorkVersion = "2026.8.19-alpha.1"
    public static let verifiedDCCVersion = "1.7.24"

    public static let smartWorkSupportedCategories: Set<FoundationCategory> = [
        .prompt, .rules, .memory, .requirements, .skills
    ]
    public static let dccSupportedCategories = smartWorkSupportedCategories
    public static let customSupportedCategories = smartWorkSupportedCategories

    public static func assess(
        client: ClientKind,
        version: String?,
        surfaces: ClientProbeSurfaces
    ) -> ClientCapabilityReport {
        let requiredAvailable: Bool
        let verifiedVersion: String
        switch client {
        case .codex:
            requiredAvailable = surfaces.accountStatus && surfaces.appServer && surfaces.projectRules
            verifiedVersion = verifiedCodexVersion
        case .claudeCode:
            requiredAvailable = surfaces.accountStatus
            verifiedVersion = verifiedClaudeVersion
        case .smartWork:
            requiredAvailable = surfaces.projectRules && surfaces.projectSkills
            verifiedVersion = verifiedSmartWorkVersion
        case .dcc:
            requiredAvailable = surfaces.projectRules && surfaces.projectSkills
            verifiedVersion = verifiedDCCVersion
        case .custom:
            requiredAvailable = surfaces.projectRules && surfaces.projectSkills
            verifiedVersion = "custom"
        }

        guard requiredAvailable else {
            return ClientCapabilityReport(
                version: version,
                verification: .unavailable,
                detail: "能力探针未通过",
                supportedCategories: []
            )
        }
        guard let version else {
            return ClientCapabilityReport(
                version: nil,
                verification: .unverified,
                detail: "客户端版本待识别",
                supportedCategories: supportedCategories(for: client)
            )
        }
        let isVerified: Bool
        switch client {
        case .codex:
            isVerified = [verifiedCodexVersion, verifiedBundledCodexVersion].contains(version)
        case .claudeCode, .smartWork, .dcc, .custom:
            isVerified = version == verifiedVersion
        }
        if isVerified {
            return ClientCapabilityReport(
                version: version,
                verification: .verified,
                detail: "v\(version) 已验证",
                supportedCategories: supportedCategories(for: client)
            )
        }

        let currentLine = version.split(separator: ".").prefix(2)
        let verifiedLine = verifiedVersion.split(separator: ".").prefix(2)
        let isCompatibleLine = currentLine.elementsEqual(verifiedLine)
        return ClientCapabilityReport(
            version: version,
            verification: isCompatibleLine ? .compatible : .unverified,
            detail: isCompatibleLine ? "v\(version) 已探测 · 待回归" : "v\(version) 未验证",
            supportedCategories: supportedCategories(for: client)
        )
    }

    private static func supportedCategories(for client: ClientKind) -> Set<FoundationCategory> {
        switch client {
        case .smartWork: smartWorkSupportedCategories
        case .dcc: dccSupportedCategories
        case .custom: customSupportedCategories
        case .codex, .claudeCode: Set(FoundationCategory.allCases)
        }
    }
}
