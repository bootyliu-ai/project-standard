import Foundation
import Testing
@testable import ProjectStandardCore

@Suite("Managed projection")
struct ManagedBlockEditorTests {
    @Test("upsert is idempotent and preserves user content")
    func upsertIsIdempotent() throws {
        let projectRoot = try FixtureProject.make(schemeIDs: ["base"])
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let project = try ProjectLoader().load(rootURL: projectRoot)
        let scheme = try #require(project.schemes.first)
        let original = "# User rules\n\nKeep this.\n"
        let block = ManagedBlockEditor.block(for: scheme, client: .codex)

        let first = ManagedBlockEditor.upsert(existing: original, block: block, client: .codex)
        let second = ManagedBlockEditor.upsert(existing: first, block: block, client: .codex)

        #expect(first == second)
        #expect(first.contains("# User rules"))
        #expect(first.contains(".project-standard/schemes/base/prompt.md"))
    }

    @Test("cancel removes only owned block")
    func cancelPreservesUserContent() throws {
        let projectRoot = try FixtureProject.make(schemeIDs: ["base"])
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let project = try ProjectLoader().load(rootURL: projectRoot)
        let scheme = try #require(project.schemes.first)
        let original = "# User rules\n\nKeep this.\n"
        let projected = ManagedBlockEditor.upsert(
            existing: original,
            block: ManagedBlockEditor.block(for: scheme, client: .codex),
            client: .codex
        )

        let cancelled = ManagedBlockEditor.remove(existing: projected, client: .codex)

        #expect(cancelled == original)
    }

    @Test("projector applies validates and cancels")
    func projectorLifecycle() throws {
        let projectRoot = try FixtureProject.make(schemeIDs: ["base"])
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let project = try ProjectLoader().load(rootURL: projectRoot)
        let scheme = try #require(project.schemes.first)
        let target = projectRoot.appendingPathComponent("AGENTS.md")
        try "# Existing\n".write(to: target, atomically: true, encoding: .utf8)
        let projector = ProjectionEngine()

        let count = try projector.apply(project: project, scheme: scheme, client: .codex)
        #expect(count.count == 4)
        #expect(projector.validate(project: project, scheme: scheme, client: .codex).count == 4)

        try projector.cancel(project: project, scheme: scheme, client: .codex)
        #expect(try String(contentsOf: target, encoding: .utf8) == "# Existing\n")
    }

    @Test("incomplete managed block is reported without overwriting user content")
    func incompleteBlockIsPreserved() throws {
        let projectRoot = try FixtureProject.make(schemeIDs: ["base"])
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let project = try ProjectLoader().load(rootURL: projectRoot)
        let scheme = try #require(project.schemes.first)
        let target = projectRoot.appendingPathComponent("AGENTS.md")
        let damaged = "# User rules\n\n\(ManagedBlockEditor.startMarker(for: .codex))\nchanged by user\n"
        try damaged.write(to: target, atomically: true, encoding: .utf8)

        #expect(throws: ProjectionEngineError.self) {
            try ProjectionEngine().apply(project: project, scheme: scheme, client: .codex)
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == damaged)
    }
}
