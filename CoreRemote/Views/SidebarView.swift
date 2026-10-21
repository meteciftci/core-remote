import SwiftData
import SwiftUI

enum SidebarItem: Hashable {
    case all
    case favorites
    case type(ConnectionType)
    case group(UUID)

    func includes(_ connection: Connection) -> Bool {
        switch self {
        case .all: true
        case .favorites: connection.isFavorite
        case .type(let type): connection.type == type
        case .group(let id): connection.group?.id == id
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
            }

            Section("Types") {
                ForEach(ConnectionType.allCases) { type in
                    row(.type(type), title: Text(verbatim: type.title), symbol: type.symbol, tint: type.tint)
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
        .badge(connections.count(where: item.includes))
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
