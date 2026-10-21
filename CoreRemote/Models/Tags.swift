import Foundation

enum Tags {
    /// Splits comma- or newline-separated text into tags.
    nonisolated static func normalize(_ text: String) -> [String] {
        normalize(text.components(separatedBy: CharacterSet(charactersIn: ",\n")))
    }

    /// Trims tags, drops empty ones and case-insensitive duplicates, keeping the first spelling and order.
    nonisolated static func normalize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Every tag in use, case-insensitively unique and sorted, with how many connections carry it.
    static func counts(in connections: [Connection]) -> [(tag: String, count: Int)] {
        var counts: [String: (tag: String, count: Int)] = [:]
        for tag in connections.flatMap(\.tags) {
            counts[tag.lowercased(), default: (tag, 0)].count += 1
        }
        return counts.values.sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }
}

extension Connection {
    func hasTag(_ tag: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }
}
