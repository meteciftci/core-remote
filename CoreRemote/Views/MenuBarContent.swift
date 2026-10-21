import AppKit
import SwiftData
import SwiftUI

/// The menu shown from the menu bar icon: favorites, recent connections and one submenu per group.
struct MenuBarContent: View {
    static let visibilityKey = "showsMenuBarIcon"
    static let recentLimit = 5

    @Environment(ConnectionLauncher.self) private var launcher
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Connection.name) private var connections: [Connection]
    @Query(sort: \ConnectionGroup.name) private var groups: [ConnectionGroup]

    var body: some View {
        let favorites = SidebarItem.favorites.filter(connections)
        let recent = Array(SidebarItem.recent.filter(connections).prefix(Self.recentLimit))
        let ungrouped = connections.filter { $0.group == nil }

        if connections.isEmpty {
            Text("No Connections")
        }

        if !favorites.isEmpty {
            Section("Favorites") {
                ForEach(favorites) { item(for: $0) }
            }
        }

        if !recent.isEmpty {
            Section("Recent") {
                ForEach(recent) { item(for: $0) }
            }
        }

        if !connections.isEmpty {
            Section("Groups") {
                ForEach(groups.filter { !$0.connections.isEmpty }) { group in
                    Menu {
                        ForEach(SidebarItem.group(group.id).filter(connections)) { item(for: $0) }
                    } label: {
                        Label(group.name, systemImage: "folder")
                    }
                }
                if !ungrouped.isEmpty {
                    Menu {
                        ForEach(ungrouped) { item(for: $0) }
                    } label: {
                        Label("No Group", systemImage: "tray")
                    }
                }
            }
        }

        Divider()

        Button("Open CoreRemote") {
            openWindow(id: MainWindow.id)
            NSApp.activate()
        }
        SettingsLink {
            Text("Settings…")
        }

        Divider()

        Button("Quit CoreRemote") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func item(for connection: Connection) -> some View {
        Button {
            Task {
                await launcher.open(connection)
                // Problems are shown in the main window, so bring it up when there is one.
                if launcher.launchProblem != nil {
                    openWindow(id: MainWindow.id)
                    NSApp.activate()
                }
            }
        } label: {
            Label(connection.name, systemImage: connection.type.symbol)
        }
    }
}
