import Foundation

public enum ProjectInitializationError: LocalizedError, Equatable {
    case notDirectory
    case incompleteStandardDirectory

    public var errorDescription: String? {
        switch self {
        case .notDirectory:
            "请选择一个项目目录"
        case .incompleteStandardDirectory:
            "项目中的 .project-standard 不完整，请先处理或移走该目录"
        }
    }
}

/// Creates the smallest valid canonical project without overwriting existing data.
/// The directory is assembled beside the final destination and installed with one
/// rename so a failed first-time setup cannot leave a partial project standard.
public struct ProjectInitializer {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    public func initializeIfNeeded(rootURL: URL) throws -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProjectInitializationError.notDirectory
        }

        let standardRoot = rootURL.appendingPathComponent(".project-standard", isDirectory: true)
        let manifestURL = standardRoot.appendingPathComponent("manifest.json")
        if fileManager.fileExists(atPath: manifestURL.path) { return false }
        if fileManager.fileExists(atPath: standardRoot.path) {
            throw ProjectInitializationError.incompleteStandardDirectory
        }

        let stagingRoot = rootURL.appendingPathComponent(
            ".project-standard.setup-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: stagingRoot) }

        let schemeRoot = stagingRoot.appendingPathComponent("schemes/base", isDirectory: true)
        try fileManager.createDirectory(
            at: schemeRoot.appendingPathComponent("skills", isDirectory: true),
            withIntermediateDirectories: true
        )

        let manifest = ProjectManifest(
            schemaVersion: 1,
            projectId: UUID().uuidString.lowercased(),
            schemes: [ManifestScheme(id: "base", name: "默认项目规范")]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(
            to: stagingRoot.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        let markdown: [(String, String)] = [
            ("prompt.md", "# 基础 Prompt\n\n"),
            ("rules.md", "# 规范与 Rules\n\n"),
            ("memory.md", "# 记忆\n\n"),
            ("requirements.md", "# 项目要求\n\n")
        ]
        for (name, contents) in markdown {
            try contents.write(
                to: schemeRoot.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }
        try Data("{\n  \"mcpServers\": {},\n  \"tools\": []\n}\n".utf8).write(
            to: schemeRoot.appendingPathComponent("tools-mcp.json"),
            options: .atomic
        )
        try Data("{\n  \"hooks\": {},\n  \"permissions\": {\n    \"additionalDirectories\": [],\n    \"allow\": [],\n    \"ask\": [],\n    \"deny\": []\n  }\n}\n".utf8).write(
            to: schemeRoot.appendingPathComponent("permissions-hooks.json"),
            options: .atomic
        )

        try fileManager.moveItem(at: stagingRoot, to: standardRoot)
        return true
    }
}
