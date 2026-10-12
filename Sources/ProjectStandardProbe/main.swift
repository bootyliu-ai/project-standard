import Darwin
import Foundation
import ProjectStandardCore

final class SnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: CodexConnectionSnapshot?

    func set(_ newValue: CodexConnectionSnapshot?) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> CodexConnectionSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

var probeEnvironment = ProcessInfo.processInfo.environment
if let executable = probeEnvironment["PROJECT_STANDARD_CODEX_EXECUTABLE"], executable.hasPrefix("/") {
    probeEnvironment["PATH"] = URL(fileURLWithPath: executable).deletingLastPathComponent().path
}
let detector = ConnectionDetector(environment: probeEnvironment)
let box = SnapshotBox()
var monitor: CodexAppServerMonitor?

if let executable = detector.executableURL(for: .codex) {
    monitor = try? CodexAppServerMonitor(executableURL: executable, cwdURL: nil) { value in
        box.set(value)
    }
    let deadline = Date().addingTimeInterval(12)
    while box.get() == nil, Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}

let snapshot = box.get()
let profiles = detector.discover(codexSnapshot: snapshot)
let safeProfiles: [[String: Any]] = profiles.map { profile in
    [
        "client": profile.client.rawValue,
        "title": profile.title,
        "source": profile.configSource,
        "version": profile.capabilities.version ?? NSNull(),
        "verification": profile.capabilities.verification.rawValue,
        "categories": profile.capabilities.supportedCategories.count
    ]
}
let result: [String: Any] = [
    "appServerActive": snapshot != nil,
    "profiles": safeProfiles
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
monitor?.stop()

if detector.executableURL(for: .codex) != nil, snapshot == nil {
    exit(2)
}
