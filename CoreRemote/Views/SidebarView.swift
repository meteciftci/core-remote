import SwiftData
import SwiftUI

enum SidebarItem: Hashable {
    case all
    case favorites
    case recent
    case type(ConnectionType)
    case group(UUID)
    case tag(String)

    static let recentLimit = 10

    /// The connections this item shows, in display order. `connections` is expected sorted by name;
    /// Recent re-sorts by last connection, newest first.
    func filter(_ connections: [Connection]) -> [Connection] {
        switch self {
        case .all: connections
        case .favorites: connections.filter(\.isFavorite)
        case .recent:
            Array(
                connections
                    .compactMap { connection in connection.lastConnectedAt.map { (connection, $0) } }
                    .sorted { $0.1 > $1.1 }
                    .prefix(Self.recentLimit)
                    .map(\.0)
            )
        case .type(let type): connections.filter { $0.type == type }
        case .group(let id): connections.filter { $0.group?.id == id }
        case .tag(let tag): connections.filter { $0.hasTag(tag) }
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    var onRenameGroup: (ConnectionGroup) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var connections: [Connection]
    @Query(sort: \ConnectionGroup.name) private var groups: [ConnectionGroup]

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                row(.all, title: Text("All Connections"), symbol: "square.stack.3d.up")
                row(.favorites, title: Text("Favorites"), symbol: "star")
                row(.recent, title: Text("Recent"), symbol: "clock")
            }

            Section("Types") {
                ForEach(ConnectionType.allCases) { type in
                    row(.type(type), title: Text(verbatim: type.title), symbol: type.symbol, tint: type.tint)
                }
            }

            let tags = Tags.counts(in: connections)
            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags, id: \.tag) { entry in
                        row(.tag(entry.tag), title: Text(verbatim: "#\(entry.tag)"), symbol: "tag")
                    }
                }
            }

            Section("Groups") {
                ForEach(groups) { group in
                    row(.group(group.id), title: Text(verbatim: group.name), symbol: "folder")
                        .contextMenu {
                            Button("Rename…") { onRenameGroup(group) }
                            Button("Delete Group", role: .destructive) { delete(group) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
    }

    private func row(_ item: SidebarItem, title: Text, symbol: String, tint: Color? = nil) -> some View {
        Label {
            title
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint ?? .accentColor)
        }
        .badge(item.filter(connections).count)
        .tag(item)
    }

    private func delete(_ group: ConnectionGroup) {
        if selection == .group(group.id) {
            selection = .all
        }
        modelContext.delete(group)
        try? modelContext.save()
    }
}
