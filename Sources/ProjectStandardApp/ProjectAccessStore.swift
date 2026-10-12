import Foundation

final class ProjectAccessStore {
    private let bookmarkURL: URL
    private(set) var activeURL: URL?
    private var isAccessing = false

    init(applicationSupportURL: URL, bookmarkName: String = "project-bookmark.data") {
        self.bookmarkURL = applicationSupportURL.appendingPathComponent(bookmarkName)
    }

    func restore() -> URL? {
        guard let data = try? Data(contentsOf: bookmarkURL) else { return nil }
        var isStale = false
        let url: URL?
        if let scoped = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            url = scoped
        } else {
            url = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
        guard let url else { return nil }
        beginAccess(to: url)
        if isStale { try? save(url) }
        return url
    }

    func save(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: bookmarkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data: Data
        if let scoped = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            data = scoped
        } else {
            data = try url.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        try data.write(to: bookmarkURL, options: .atomic)
        beginAccess(to: url)
    }

    func useWithoutPersisting(_ url: URL) {
        beginAccess(to: url)
    }

    func stop() {
        if isAccessing { activeURL?.stopAccessingSecurityScopedResource() }
        activeURL = nil
        isAccessing = false
    }

    private func beginAccess(to url: URL) {
        stop()
        activeURL = url
        isAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit { stop() }
}
