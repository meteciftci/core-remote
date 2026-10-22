import Foundation
import SwiftData

/// How the connection list is sorted.
nonisolated enum ConnectionSort: String, CaseIterable, Identifiable, Sendable {
    /// The order the user dragged connections into.
    case manual
    case name
    /// Most recently connected first; never-used connections last, by name.
    case recent

    static let storageKey = "connectionSort"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: String(localized: "Manual")
        case .name: String(localized: "Name")
        case .recent: String(localized: "Last Connected")
        }
    }
}

enum ConnectionOrder {
    static func sorted(_ connections: [Connection], by sort: ConnectionSort) -> [Connection] {
        connections.sorted { a, b in
            switch sort {
            case .manual:
                if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            case .name:
                break
            case .recent:
                switch (a.lastConnectedAt, b.lastConnectedAt) {
                case let (x?, y?) where x != y: return x > y
                case (.some, nil): return true
                case (nil, .some): return false
                default: break
                }
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// The full manual order after dragging rows of a filtered list. Rows that aren't visible
    /// keep their places; the visible ones are rearranged within the slots they occupy.
    nonisolated static func reorder(all: [UUID], visible: [UUID], from source: IndexSet, to destination: Int) -> [UUID] {
        var moved = visible
        moved.move(fromOffsets: source, toOffset: destination)
        let visibleSet = Set(visible)
        var replacements = moved.makeIterator()
        return all.map { id in visibleSet.contains(id) ? replacements.next() ?? id : id }
    }

    /// Saves a new manual order as consecutive indexes.
    static func apply(_ order: [UUID], to connections: [Connection]) {
        let byID = Dictionary(uniqueKeysWithValues: connections.map { ($0.id, $0) })
        for (index, id) in order.enumerated() {
            byID[id]?.sortIndex = index
        }
    }

    /// The index that puts a new connection after every existing one.
    static func nextIndex(in context: ModelContext) -> Int {
        var descriptor = FetchDescriptor<Connection>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)])
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor).first?.sortIndex) ?? -1) + 1
    }
}
