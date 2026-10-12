import Foundation
import Testing
@testable import ProjectStandardCore

@Suite("Project file watcher")
struct ProjectFileWatcherTests {
    @Test("event watcher reports a project file change")
    func reportsChange() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-standard-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let signal = DispatchSemaphore(value: 0)
        let watcher = try ProjectFileWatcher(rootURL: root) { _ in signal.signal() }
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.15)
        try "changed".write(
            to: root.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        #expect(signal.wait(timeout: .now() + 4) == .success)
    }
}
