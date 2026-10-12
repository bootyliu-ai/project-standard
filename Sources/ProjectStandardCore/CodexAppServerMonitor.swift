import Darwin
import Foundation

struct CodexAppServerStateReducer {
    private(set) var authMode: String?
    private(set) var planType: String?
    private(set) var modelProvider: String?
    private(set) var requiresOpenAIAuth: Bool?
    private(set) var receivedAccount = false
    private(set) var receivedConfig = false

    mutating func consumeAccount(_ result: [String: Any]) {
        receivedAccount = true
        requiresOpenAIAuth = result["requiresOpenaiAuth"] as? Bool
        if let account = result["account"] as? [String: Any] {
            authMode = account["type"] as? String
            planType = account["planType"] as? String
        } else {
            authMode = nil
            planType = nil
        }
    }

    mutating func consumeConfig(_ result: [String: Any]) {
        receivedConfig = true
        let config = result["config"] as? [String: Any]
        modelProvider = config?["model_provider"] as? String
    }

    mutating func consumeAccountUpdated(_ params: [String: Any]) {
        receivedAccount = true
        authMode = params["authMode"] as? String
        planType = params["planType"] as? String
    }

    var snapshot: CodexConnectionSnapshot? {
        guard receivedAccount && receivedConfig else { return nil }
        return CodexConnectionSnapshot(
            authMode: authMode,
            planType: planType,
            modelProvider: modelProvider,
            requiresOpenAIAuth: requiresOpenAIAuth
        )
    }
}

public enum CodexAppServerMonitorError: LocalizedError {
    case unavailable

    public var errorDescription: String? { "Codex App Server 不可用" }
}

/// Maintains one initialized Codex App Server connection. It consumes only
/// non-secret account/routing fields and watches the Codex config directory
/// through App Server so sandboxed hosts do not need direct home-directory access.
public final class CodexAppServerMonitor: @unchecked Sendable {
    private enum RequestKind {
        case initialize
        case account
        case config
        case watch
    }

    private let executableURL: URL
    private let cwdURL: URL?
    private let codexHomeURL: URL
    private let callback: @Sendable (CodexConnectionSnapshot?) -> Void
    private let queue = DispatchQueue(label: "com.projectstandard.codex-app-server", qos: .utility)
    private let lock = NSLock()
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    private var pending: [Int: RequestKind] = [:]
    private var nextID = 1
    private var state = CodexAppServerStateReducer()
    private var refreshWorkItem: DispatchWorkItem?
    private var stopped = false

    public init(
        executableURL: URL,
        cwdURL: URL?,
        codexHomeURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        callback: @escaping @Sendable (CodexConnectionSnapshot?) -> Void
    ) throws {
        guard executableURL.isFileURL, executableURL.path.hasPrefix("/") else {
            throw CodexAppServerMonitorError.unavailable
        }
        self.executableURL = executableURL
        self.cwdURL = cwdURL
        self.codexHomeURL = codexHomeURL ?? Self.codexHomeURL(environment: environment)
        self.callback = callback
        try start()
    }

    deinit { stop() }

    public func stop() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        let runningProcess = process
        let runningOutput = output
        process = nil
        input = nil
        output = nil
        lock.unlock()

        runningOutput?.fileHandleForReading.readabilityHandler = nil
        if runningProcess?.isRunning == true { runningProcess?.terminate() }
    }

    private func start() throws {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        var processEnvironment = ProcessInfo.processInfo.environment
        processEnvironment["CODEX_HOME"] = codexHomeURL.path
        process.environment = processEnvironment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let monitor = self else { return }
            monitor.queue.async { monitor.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            let shouldNotify = !self.stopped
            self.lock.unlock()
            if shouldNotify { self.queue.async { self.callback(nil) } }
        }
        do { try process.run() } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw CodexAppServerMonitorError.unavailable
        }
        lock.lock()
        self.process = process
        self.input = input
        self.output = output
        lock.unlock()
        queue.async { [weak self] in self?.sendInitialize() }
    }

    private func sendInitialize() {
        sendRequest(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "project_standard",
                    "title": "Project Standard",
                    "version": "1.0.0"
                ]
            ],
            kind: .initialize
        )
    }

    private func completeHandshake() {
        send(["method": "initialized"])
        refreshState()
        sendRequest(
            method: "fs/watch",
            params: ["path": codexHomeURL.path, "watchId": "project-standard-codex-home"],
            kind: .watch
        )
    }

    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.refreshState() }
        refreshWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func refreshState() {
        sendRequest(
            method: "account/read",
            params: ["refreshToken": false],
            kind: .account
        )
        var configParams: [String: Any] = ["includeLayers": false]
        if let cwdURL { configParams["cwd"] = cwdURL.path }
        sendRequest(method: "config/read", params: configParams, kind: .config)
    }

    private func sendRequest(method: String, params: [String: Any], kind: RequestKind) {
        let id = nextID
        nextID += 1
        pending[id] = kind
        send(["method": method, "id": id, "params": params])
    }

    private func send(_ object: [String: Any]) {
        lock.lock()
        let writer = stopped ? nil : input?.fileHandleForWriting
        lock.unlock()
        guard let writer,
              var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        try? writer.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            consume(object)
        }
    }

    private func consume(_ object: [String: Any]) {
        if let id = object["id"] as? Int, let kind = pending.removeValue(forKey: id) {
            guard object["error"] == nil else { return }
            let result = object["result"] as? [String: Any] ?? [:]
            switch kind {
            case .initialize:
                completeHandshake()
            case .account:
                state.consumeAccount(result)
                publishIfReady()
            case .config:
                state.consumeConfig(result)
                publishIfReady()
            case .watch:
                break
            }
            return
        }

        guard let method = object["method"] as? String else { return }
        let params = object["params"] as? [String: Any] ?? [:]
        switch method {
        case "account/updated":
            state.consumeAccountUpdated(params)
            publishIfReady()
            scheduleRefresh()
        case "fs/changed":
            guard params["watchId"] as? String == "project-standard-codex-home" else { return }
            scheduleRefresh()
        default:
            break
        }
    }

    private func publishIfReady() {
        guard let snapshot = state.snapshot else { return }
        callback(snapshot)
    }

    private static func codexHomeURL(environment: [String: String]) -> URL {
        if let configured = environment["CODEX_HOME"], configured.hasPrefix("/") {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        if let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
                .appendingPathComponent(".codex", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }
}
