import SwiftData
import SwiftUI

@main
struct CoreRemoteApp: App {
    @FocusedValue(\.appActions) private var actions

    init() {
        LaunchFiles.cleanUp()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 440)
        }
        .modelContainer(for: [Connection.self, ConnectionGroup.self])
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection") { actions?.newConnection() }
                    .keyboardShortcut("n")
                    .disabled(actions == nil)
                Button("New Group") { actions?.newGroup() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(actions == nil)
            }
            CommandGroup(replacing: .importExport) {
                Button("Import…") { actions?.importBackup() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(actions == nil)
                Button("Export…") { actions?.exportBackup() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(actions == nil)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// Window actions exposed to the menu bar commands.
struct AppActions {
    var newConnection: () -> Void
    var newGroup: () -> Void
    var importBackup: () -> Void
    var exportBackup: () -> Void
}

extension FocusedValues {
    @Entry var appActions: AppActions?
}
