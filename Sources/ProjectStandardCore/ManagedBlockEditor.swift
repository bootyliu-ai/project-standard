import Foundation

public enum ManagedBlockEditor {
    public static func startMarker(for client: ClientKind) -> String {
        startMarker(identifier: client.rawValue)
    }

    public static func endMarker(for client: ClientKind) -> String {
        endMarker(identifier: client.rawValue)
    }

    public static func startMarker(identifier: String) -> String {
        "<!-- project-standard:start client=\(identifier) -->"
    }

    public static func endMarker(identifier: String) -> String {
        "<!-- project-standard:end client=\(identifier) -->"
    }

    public static func block(for scheme: Scheme, client: ClientKind) -> String {
        block(for: scheme, identifier: client.rawValue)
    }

    public static func block(for scheme: Scheme, identifier: String) -> String {
        let readable = scheme.categories.filter {
            [.prompt, .rules, .memory, .requirements].contains($0.category)
        }
        let paths = readable.map { "- `\($0.relativePath)`" }.joined(separator: "\n")
        return """
        \(startMarker(identifier: identifier))
        ## Project Standard · \(scheme.name)

        Before interpreting or acting on project requests, read these canonical project files:

        \(paths)

        Treat `.project-standard/` as the source of truth. Never copy credentials into project files.
        \(endMarker(identifier: identifier))
        """
    }

    public static func upsert(existing: String, block: String, client: ClientKind) -> String {
        upsert(existing: existing, block: block, identifier: client.rawValue)
    }

    public static func upsert(existing: String, block: String, identifier: String) -> String {
        let cleaned = remove(existing: existing, identifier: identifier)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return block + "\n" }
        return cleaned + "\n\n" + block + "\n"
    }

    public static func remove(existing: String, client: ClientKind) -> String {
        remove(existing: existing, identifier: client.rawValue)
    }

    public static func remove(existing: String, identifier: String) -> String {
        let start = startMarker(identifier: identifier)
        let end = endMarker(identifier: identifier)
        guard let startRange = existing.range(of: start),
              let endRange = existing.range(of: end, range: startRange.upperBound..<existing.endIndex) else {
            return existing
        }
        var result = existing
        result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : result.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    public static func contains(scheme: Scheme, in existing: String, client: ClientKind) -> Bool {
        contains(scheme: scheme, in: existing, identifier: client.rawValue)
    }

    public static func contains(scheme: Scheme, in existing: String, identifier: String) -> Bool {
        let expected = block(for: scheme, identifier: identifier)
        return existing.contains(expected)
    }
}
