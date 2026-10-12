import Foundation

public enum ProjectLoadError: LocalizedError, Equatable {
    case missingManifest
    case unsupportedSchema(Int)
    case noSchemes
    case duplicateSchemeID(String)

    public var errorDescription: String? {
        switch self {
        case .missingManifest:
            "所选目录没有 .project-standard/manifest.json"
        case .unsupportedSchema(let version):
            "不支持 schemaVersion \(version)"
        case .noSchemes:
            "项目至少需要一个方案"
        case .duplicateSchemeID(let id):
            "方案 ID 重复：\(id)"
        }
    }
}

public struct ProjectLoader {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load(rootURL: URL) throws -> LoadedProject {
        let standardRoot = rootURL.appendingPathComponent(".project-standard", isDirectory: true)
        let manifestURL = standardRoot.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw ProjectLoadError.missingManifest
        }

        let manifest = try JSONDecoder().decode(
            ProjectManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.schemaVersion == 1 else {
            throw ProjectLoadError.unsupportedSchema(manifest.schemaVersion)
        }
        guard !manifest.schemes.isEmpty else { throw ProjectLoadError.noSchemes }

        var seen = Set<String>()
        for scheme in manifest.schemes where !seen.insert(scheme.id).inserted {
            throw ProjectLoadError.duplicateSchemeID(scheme.id)
        }

        let schemes = manifest.schemes.map { scheme in
            Scheme(
                id: scheme.id,
                name: scheme.name,
                categories: makeCategories(
                    standardRoot: standardRoot,
                    scheme: scheme
                )
            )
        }
        return LoadedProject(rootURL: rootURL, manifest: manifest, schemes: schemes)
    }

    private func makeCategories(standardRoot: URL, scheme: ManifestScheme) -> [CategorySource] {
        FoundationCategory.allCases.map { category in
            let schemeRelativePath = relativePath(for: category, in: scheme)
            let relativePath = ".project-standard/\(schemeRelativePath)"
            let url = standardRoot.appendingPathComponent(schemeRelativePath)
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return CategorySource(
                category: category,
                relativePath: relativePath + (isDirectory.boolValue ? "/" : ""),
                url: url,
                itemCount: exists ? countItems(at: url, category: category, isDirectory: isDirectory.boolValue) : 0,
                exists: exists
            )
        }
    }

    private func relativePath(for category: FoundationCategory, in scheme: ManifestScheme) -> String {
        guard let sources = scheme.sources else {
            return "schemes/\(scheme.id)/\(category.defaultFileName)"
        }
        return switch category {
        case .prompt: sources.prompt
        case .rules: sources.rules
        case .memory: sources.memory
        case .requirements: sources.requirements
        case .skills: sources.skills
        case .toolsMcp: sources.toolsMcp
        case .permissionsHooks: sources.permissionsHooks
        }
    }

    private func countItems(at url: URL, category: FoundationCategory, isDirectory: Bool) -> Int {
        if isDirectory {
            let entries = (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            return entries.count
        }
        if url.pathExtension.lowercased() == "json",
           let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) {
            if let dictionary = object as? [String: Any] {
                let nestedCount = dictionary.values.reduce(0) { result, value in
                    if let dictionary = value as? [String: Any] { return result + dictionary.count }
                    if let array = value as? [Any] { return result + array.count }
                    return result + 1
                }
                return max(1, nestedCount)
            }
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 1 }
        let listItems = text.split(separator: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("- ") || trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
        }
        return max(1, listItems.count)
    }
}
