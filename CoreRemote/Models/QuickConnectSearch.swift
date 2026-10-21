import Foundation

/// Orders connections for the quick connect palette.
enum QuickConnectSearch {
    /// With an empty query: recently used first, then favorites, then the rest by name.
    /// With a query: best match first (name prefix, word in the name, anywhere in the name,
    /// then host, user or group), ties broken by recent use and name.
    static func results(for query: String, in connections: [Connection]) -> [Connection] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let scored = connections.compactMap { connection -> (Connection, Int)? in
            guard !query.isEmpty else { return (connection, connection.isFavorite ? 0 : 1) }
            return score(connection, for: query).map { (connection, $0) }
        }
        return scored.sorted { lhs, rhs in
            if query.isEmpty, (lhs.0.lastConnectedAt != nil) != (rhs.0.lastConnectedAt != nil) {
                return lhs.0.lastConnectedAt != nil
            }
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            let lhsDate = lhs.0.lastConnectedAt ?? .distantPast
            let rhsDate = rhs.0.lastConnectedAt ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
        }
        .map(\.0)
    }

    /// Lower is better; `nil` when nothing matches.
    private static func score(_ connection: Connection, for query: String) -> Int? {
        let name = connection.name
        if name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil { return 0 }
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }) {
            return 1
        }
        if name.localizedStandardContains(query) { return 2 }
        let others = [connection.host, connection.username, connection.group?.name ?? ""]
        if others.contains(where: { $0.localizedStandardContains(query) }) { return 3 }
        return nil
    }
}
