import AppIntents
import AppKit
import SwiftData
import SwiftUI

@main
struct CoreRemoteApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @FocusedValue(\.appActions) private var actions
    @AppStorage(MenuBarContent.visibilityKey) private var showsMenuBarIcon = true
    @State private var launcher: ConnectionLauncher

    private let container: ModelContainer

    init() {
        LaunchFiles.cleanUp()
        container = Self.makeContainer()
        let launcher = ConnectionLauncher()
        _launcher = State(initialValue: launcher)
        QuickConnectPanel.shared.configure(container: container, launcher: launcher)
        // Shortcuts, Siri and Spotlight use the same store and launcher as the windows.
        let container = container
        AppDependencyManager.shared.add(dependency: container)
        AppDependencyManager.shared.add(dependency: launcher)
        AppDelegate.urlHandler = { url in
            Task { await ConnectURL.handle(url, container: container, launcher: launcher) }
        }
    }

    private static func makeContainer() -> ModelContainer {
        do {
            #if DEBUG
            if DemoData.isEnabled {
                return try DemoData.makeContainer()
            }
            #endif
            return try AppSchema.container()
        } catch {
            fatalError("Could not open the connection store: \(error)")
        }
    }

    var body: some Scene {
        // A single window, so the menu bar's "Open CoreRemote" brings it back instead of adding another.
        Window("CoreRemote", id: MainWindow.id) {
            ContentView()
                .frame(minWidth: 720, minHeight: 440)
                .environment(launcher)
        }
        .defaultSize(width: 960, height: 600)
        // Open the window on every launch, even if it was closed when the app last quit.
        .defaultLaunchBehavior(.presented)
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
                Divider()
                Button("Import from SSH Config…") { actions?.importSSHConfig() }
                    .disabled(actions == nil)
                Button("Import .rdp Files…") { actions?.importRDPFiles() }
                    .disabled(actions == nil)
            }
        }

        WindowGroup(id: EditorWindow.id, for: EditorTarget.self) { $target in
            EditorWindowContent(target: target)
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
        }
        .modelContainer(container)

        MenuBarExtra("CoreRemote", systemImage: "network", isInserted: $showsMenuBarIcon) {
            MenuBarContent()
                .environment(launcher)
        }
        .modelContainer(container)
    }
}

enum MainWindow {
    static let id = "main"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the app once its store and launcher exist.
    static var urlHandler: ((URL) -> Void)?

    /// `coreremote://connect/…` links, such as the ones in exported shortcuts.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { Self.urlHandler?($0) }
    }

    /// Keep running in the menu bar after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Window actions exposed to the menu bar commands.
struct AppActions {
    var newConnection: () -> Void
    var newGroup: () -> Void
    var importBackup: () -> Void
    var importSSHConfig: () -> Void
    var importRDPFiles: () -> Void
    var exportBackup: () -> Void
}

extension FocusedValues {
    @Entry var appActions: AppActions?
}
