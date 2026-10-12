import Foundation
import Testing
@testable import ProjectStandardCore

@Suite("Project loader")
struct ProjectLoaderTests {
    @Test("loads three schemes and seven categories")
    func loadsProject() throws {
        let root = try FixtureProject.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try ProjectLoader().load(rootURL: root)

        #expect(project.manifest.projectId == "fixture")
        #expect(project.schemes.count == 3)
        #expect(project.schemes.allSatisfy { $0.categories.count == 7 })
        #expect(project.schemes.allSatisfy { $0.existingCategoryCount == 7 })
    }

    @Test("rejects duplicate scheme IDs")
    func rejectsDuplicates() throws {
        let root = try FixtureProject.make(schemeIDs: ["base", "base"])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: ProjectLoadError.duplicateSchemeID("base")) {
            try ProjectLoader().load(rootURL: root)
        }
    }

    @Test("initializes an ordinary project once and loads all seven categories")
    func initializesOrdinaryProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-standard-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let initializer = ProjectInitializer()
        #expect(try initializer.initializeIfNeeded(rootURL: root))
        #expect(try !initializer.initializeIfNeeded(rootURL: root))

        let project = try ProjectLoader().load(rootURL: root)
        #expect(project.schemes.count == 1)
        #expect(project.schemes.first?.name == "默认项目规范")
        #expect(project.schemes.first?.categories.count == 7)
        #expect(project.schemes.first?.existingCategoryCount == 7)
    }

    @Test("does not overwrite an incomplete project standard directory")
    func preservesIncompleteStandardDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-standard-incomplete-\(UUID().uuidString)", isDirectory: true)
        let standard = root.appendingPathComponent(".project-standard", isDirectory: true)
        try FileManager.default.createDirectory(at: standard, withIntermediateDirectories: true)
        let sentinel = standard.appendingPathComponent("keep.txt")
        try "keep".write(to: sentinel, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: ProjectInitializationError.incompleteStandardDirectory) {
            try ProjectInitializer().initializeIfNeeded(rootURL: root)
        }
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
        #expect(!FileManager.default.fileExists(atPath: standard.appendingPathComponent("manifest.json").path))
    }
}

enum FixtureProject {
    static func make(schemeIDs: [String] = ["base", "design", "review"]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-standard-test-\(UUID().uuidString)", isDirectory: true)
        let standard = root.appendingPathComponent(".project-standard", isDirectory: true)
        try FileManager.default.createDirectory(at: standard, withIntermediateDirectories: true)
        let manifest = ProjectManifest(
            schemaVersion: 1,
            projectId: "fixture",
            schemes: schemeIDs.map { ManifestScheme(id: $0, name: $0.capitalized) }
        )
        try JSONEncoder().encode(manifest).write(
            to: standard.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        for id in Set(schemeIDs) {
            let scheme = standard.appendingPathComponent("schemes/\(id)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: scheme.appendingPathComponent("skills", isDirectory: true),
                withIntermediateDirectories: true
            )
            for name in ["prompt.md", "rules.md", "memory.md", "requirements.md"] {
                try "# Test\n\n- one\n".write(
                    to: scheme.appendingPathComponent(name),
                    atomically: true,
                    encoding: .utf8
                )
            }
            try "# Skill".write(
                to: scheme.appendingPathComponent("skills/README.md"),
                atomically: true,
                encoding: .utf8
            )
            try Data("{\"tools\":[],\"mcpServers\":{}}".utf8).write(
                to: scheme.appendingPathComponent("tools-mcp.json")
            )
            try Data("{\"permissions\":{},\"hooks\":{}}".utf8).write(
                to: scheme.appendingPathComponent("permissions-hooks.json")
            )
        }
        return root
    }
}
