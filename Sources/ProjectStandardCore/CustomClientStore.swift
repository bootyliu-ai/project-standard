import Foundation

public final class CustomClientStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> [CustomClientDefinition] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([CustomClientDefinition].self, from: data)) ?? []
    }

    public func save(_ clients: [CustomClientDefinition]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(clients).write(to: fileURL, options: .atomic)
    }
}
