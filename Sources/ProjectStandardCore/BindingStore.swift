import Foundation

public final class BindingStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func load() -> [String: BindingRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? decoder.decode([String: BindingRecord].self, from: data)) ?? [:]
    }

    public func save(_ bindings: [String: BindingRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(bindings).write(to: fileURL, options: .atomic)
    }

    public static func key(projectID: String, profileID: String) -> String {
        "\(projectID)::\(profileID)"
    }
}
