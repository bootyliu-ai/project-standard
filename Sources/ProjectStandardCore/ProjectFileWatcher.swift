import CoreServices
import Darwin
import Foundation

/// A small FSEvents wrapper. It watches one authorized project root and emits
/// coalesced change notifications; AppModel then fingerprints only canonical
/// and projected paths so unrelated build/git activity is ignored.
public final class ProjectFileWatcher: @unchecked Sendable {
    public struct Event: Sendable {
        public let mustRescan: Bool
    }

    enum WatchError: LocalizedError {
        case unavailable

        var errorDescription: String? { "无法启动项目文件监听" }
    }

    private var stream: FSEventStreamRef?
    private let rootURL: URL
    private let callback: @Sendable (Event) -> Void
    private let queue = DispatchQueue(label: "com.projectstandard.fsevents", qos: .utility)
    private let lock = NSLock()
    private var pendingMustRescan = false
    private var debounceWorkItem: DispatchWorkItem?
    private var fallbackSources: [DispatchSourceFileSystemObject] = []
    private var isStopped = false

    public init(rootURL: URL, callback: @escaping @Sendable (Event) -> Void) throws {
        self.rootURL = rootURL
        self.callback = callback
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagWatchRoot |
            kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil,
            Self.eventCallback,
            &context,
            [rootURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else {
            throw WatchError.unavailable
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            guard startVnodeFallback() else { throw WatchError.unavailable }
            return
        }
    }

    deinit { stop() }

    public func stop() {
        lock.lock()
        isStopped = true
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        lock.unlock()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        for source in fallbackSources { source.cancel() }
        fallbackSources.removeAll()
    }

    private static let eventCallback: FSEventStreamCallback = { _, info, count, _, rawFlags, _ in
        guard let info else { return }
        let watcher = Unmanaged<ProjectFileWatcher>.fromOpaque(info).takeUnretainedValue()
        var mustRescan = false
        for index in 0..<count {
            let flags = rawFlags[index]
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 ||
                flags & FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped) != 0 ||
                flags & FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped) != 0 ||
                flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
                mustRescan = true
                break
            }
        }
        watcher.schedule(mustRescan: mustRescan)
    }

    private func schedule(mustRescan: Bool) {
        lock.lock()
        guard !isStopped else { lock.unlock(); return }
        pendingMustRescan = pendingMustRescan || mustRescan
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let rescan = self.pendingMustRescan
            self.pendingMustRescan = false
            self.debounceWorkItem = nil
            self.lock.unlock()
            if self.stream == nil { _ = self.startVnodeFallback() }
            DispatchQueue.main.async { self.callback(Event(mustRescan: rescan)) }
        }
        debounceWorkItem = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 0.65, execute: work)
    }

    @discardableResult
    private func startVnodeFallback() -> Bool {
        lock.lock()
        let stopped = isStopped
        lock.unlock()
        guard !stopped else { return false }
        for source in fallbackSources { source.cancel() }
        fallbackSources.removeAll()

        var directories = [rootURL]
        if let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    directories.append(url)
                }
            }
        }

        for directory in directories {
            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
                queue: queue
            )
            source.setEventHandler { [weak self] in self?.schedule(mustRescan: false) }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            fallbackSources.append(source)
        }
        return !fallbackSources.isEmpty
    }
}
