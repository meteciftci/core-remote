import SwiftData
import SwiftUI

struct ConnectionListView: View {
    var filter: SidebarItem
    var title: String
    var onConnect: (Connection) -> Void
    var onEdit: (Connection?) -> Void
    var onNewGroup: () -> Void
    var onCopyCommand: (Connection) -> Void
    var onFileTransfer: (Connection) -> Void
    var onImport: () -> Void
    var onExport: () -> Void
    var onImportSSHConfig: () -> Void
    var onImportRDPFiles: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ReachabilityMonitor.self) private var reachability
    @Query(sort: \Connection.name, order: .forward) private var allConnections: [Connection]
    @State private var selection = Set<UUID>()
    @State private var searchText = ""
    @State private var pendingDeletion: [Connection] = []

    private var connections: [Connection] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return filter.filter(allConnections).filter { connection in
            guard !query.isEmpty else { return true }
            let fields = [connection.name, connection.host, connection.username, connection.group?.name ?? "", connection.notes]
            return (fields + connection.tags).contains { $0.localizedStandardContains(query) }
        }
    }

    private var selectedConnections: [Connection] {
        connections.filter { selection.contains($0.id) }
    }

    var body: some View {
        content
            .navigationTitle(title)
            .navigationSubtitle(Text("\(connections.count) connections"))
            .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search name, host or user"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Settings (⌘,)")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Import…", systemImage: "square.and.arrow.down", action: onImport)
                        Button("Export…", systemImage: "square.and.arrow.up", action: onExport)
                            .disabled(allConnections.isEmpty)
                        Divider()
                        Button("Import from SSH Config…", systemImage: "terminal", action: onImportSSHConfig)
                        Button("Import .rdp Files…", systemImage: "display", action: onImportRDPFiles)
                    } label: {
                        Label("Backup", systemImage: "arrow.up.arrow.down.circle")
                    }
                    .help("Import or export connections")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        selectedConnections.first.map(onConnect)
                    } label: {
                        Label("Connect", systemImage: "play.fill")
                    }
                    .disabled(selectedConnections.count != 1)
                    .help("Connect (Return)")
                    Button {
                        onEdit(nil)
                    } label: {
                        Label("New Connection", systemImage: "link.badge.plus")
                    }
                    .help("New Connection (⌘N)")
                    Button(action: onNewGroup) {
                        Label("New Group", systemImage: "folder.badge.plus")
                    }
                    .help("New Group (⇧⌘N)")
                }
            }
            .confirmationDialog(
                deletionTitle,
                isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { delete(pendingDeletion) }
            } message: {
                Text("Saved passwords are removed from the Keychain too. This can't be undone.")
            }
            .onDeleteCommand {
                pendingDeletion = selectedConnections
            }
    }

    @ViewBuilder
    private var content: some View {
        if allConnections.isEmpty {
            ContentUnavailableView {
                Label("No Connections", systemImage: "network")
            } description: {
                Text("Add your first SSH or RDP connection.")
            } actions: {
                Button("Add Connection") { onEdit(nil) }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        } else if connections.isEmpty {
            if searchText.isEmpty {
                ContentUnavailableView("Nothing Here", systemImage: "tray", description: Text("No connections match this filter."))
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        } else {
            List(selection: $selection) {
                ForEach(connections) { connection in
                    ConnectionRow(connection: connection, status: reachability.status(for: connection))
                        .tag(connection.id)
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()
            .contextMenu(forSelectionType: UUID.self) { ids in
                menu(for: connections.filter { ids.contains($0.id) })
            } primaryAction: { ids in
                // Double-click or Return.
                if ids.count == 1, let connection = connections.first(where: { ids.contains($0.id) }) {
                    onConnect(connection)
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for items: [Connection]) -> some View {
        if items.count == 1, let connection = items.first {
            Button("Connect", systemImage: "play.fill") { onConnect(connection) }
            Button("Edit…", systemImage: "pencil") { onEdit(connection) }
            Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(connection) }
            if connection.type == .ssh {
                Button("File Transfer", systemImage: "folder") { onFileTransfer(connection) }
                Button("Copy SSH Command", systemImage: "doc.on.doc") { onCopyCommand(connection) }
            }

            Divider()
            Button(
                connection.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: connection.isFavorite ? "star.slash" : "star"
            ) {
                connection.isFavorite.toggle()
            }
            Divider()
        }
        if !items.isEmpty {
            Button("Delete…", systemImage: "trash", role: .destructive) { pendingDeletion = items }
        }
    }

    private var deletionTitle: String {
        if pendingDeletion.count == 1, let connection = pendingDeletion.first {
            return String(localized: "Delete “\(connection.name)”?")
        }
        return String(localized: "Delete \(pendingDeletion.count) connections?")
    }

    private func duplicate(_ connection: Connection) {
        let copy = Connection(
            name: String(localized: "\(connection.name) Copy"),
            host: connection.host,
            type: connection.type,
            port: connection.port,
            username: connection.username,
            keyFilePath: connection.keyFilePath,
            ignoreCertificateErrors: connection.ignoreCertificateErrors,
            notes: connection.notes,
            tags: connection.tags,
            isFavorite: connection.isFavorite,
            group: connection.group
        )
        copy.rdpOverrides = connection.rdpOverrides
        modelContext.insert(copy)
        let store = KeychainPasswordStore.shared
        if let password = store.password(for: connection.id) {
            try? store.setPassword(password, for: copy.id)
        }
        try? modelContext.save()
        selection = [copy.id]
    }

    private func delete(_ items: [Connection]) {
        for connection in items {
            try? KeychainPasswordStore.shared.setPassword(nil, for: connection.id)
            selection.remove(connection.id)
            modelContext.delete(connection)
        }
        try? modelContext.save()
        pendingDeletion = []
    }
}
