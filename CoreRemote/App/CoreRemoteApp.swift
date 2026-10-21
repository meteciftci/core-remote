import SwiftData
import SwiftUI

@main
struct CoreRemoteApp: App {
    @FocusedValue(\.appActions) private var actions

    private let container: ModelContainer

    init() {
        LaunchFiles.cleanUp()
        do {
            #if DEBUG
            if DemoData.isEnabled {
                container = try DemoData.makeContainer()
                return
            }
            #endif
            container = try ModelContainer(for: Connection.self, ConnectionGroup.self)
        } catch {
            fatalError("Could not open the connection store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 440)
        }
        .defaultSize(width: 960, height: 600)
        .modelContainer(container)
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
        .modelContainer(container)
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
