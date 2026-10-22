import AppKit
import KeyboardShortcuts
import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(TerminalApp.storageKey) private var terminalApp: TerminalApp = TerminalApp.defaultApp
    @State private var installedTerminals: Set<TerminalApp> = [.terminal]
    @AppStorage(FileTransferClient.storageKey) private var fileTransferClient = ""
    @State private var fileTransferApps: [FileTransferApp] = []
    @AppStorage(RDPClient.storageKey) private var rdpClient: RDPClient = RDPClient.defaultClient
    @AppStorage(WindowsApp.minimizeStorageKey) private var minimizesMainWindow = true
    @State private var isAccessibilityTrusted = WindowsAppWindowMinimizer.isTrusted
    @State private var installed: Set<RDPClient> = []
    @State private var confirmsClearHistory = false
    @AppStorage(MenuBarContent.visibilityKey) private var showsMenuBarIcon = true
    @AppStorage(ReachabilityMonitor.storageKey) private var checksReachability = true

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Connection> { $0.lastConnectedAt != nil }) private var recentConnections: [Connection]

    private var hasHistory: Bool { !recentConnections.isEmpty }

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { general }
            Tab("Credentials", systemImage: "person.badge.key") { CredentialsSettings() }
        }
    }

    private var general: some View {
        Form {
            Section {
                Picker("SSH terminal", selection: $terminalApp) {
                    ForEach(TerminalApp.allCases) { app in
                        Text(verbatim: app.title)
                            .tag(app)
                            .disabled(!installedTerminals.contains(app))
                    }
                }
                .pickerStyle(.radioGroup)

                if !installedTerminals.contains(.iTerm2), let brewCommand = TerminalApp.iTerm2.brewCommand {
                    LabeledContent {
                        Button("Copy brew Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(brewCommand, forType: .string)
                        }
                    } label: {
                        Label("\(TerminalApp.iTerm2.title) is not installed", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("The saved password is entered automatically in both. The first iTerm2 connection asks once for permission to control iTerm2. If iTerm2 is removed, connections open in Terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("File transfer", selection: $fileTransferClient) {
                    Text("Automatic").tag(FileTransferClient.automatic.storedValue)
                    Text("sftp in the SSH terminal").tag(FileTransferClient.terminal.storedValue)
                    if !fileTransferApps.isEmpty {
                        Divider()
                        ForEach(fileTransferApps) { app in
                            Text(verbatim: app.name).tag(FileTransferClient.app(app.bundleIdentifier).storedValue)
                        }
                    }
                }

                if fileTransferApps.isEmpty {
                    LabeledContent {
                        Button("Copy brew Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("brew install --cask cyberduck", forType: .string)
                        }
                    } label: {
                        Label("No file transfer app such as Cyberduck is installed", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("\"File Transfer\" in an SSH connection's menu opens its files here. Automatic picks an installed file transfer app, or sftp in the terminal if there is none. Apps get the server and user name; the saved password is copied to the clipboard for 30 seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("RDP client", selection: $rdpClient) {
                    ForEach(RDPClient.allCases) { client in
                        Text(verbatim: client.title).tag(client)
                    }
                }
                .pickerStyle(.radioGroup)

                if !installed.contains(rdpClient) {
                    LabeledContent {
                        Button("Copy brew Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(rdpClient.brewCommand, forType: .string)
                        }
                    } label: {
                        Label("\(rdpClient.title) is not installed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } footer: {
                Text(rdpClient == .windowsApp
                     ? "Windows App asks for the password itself; CoreRemote copies it to the clipboard for 30 seconds."
                     : "FreeRDP receives the saved password directly and doesn't show Windows App's confirmation dialogs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if rdpClient == .windowsApp {
                Section {
                    Toggle("Minimize the Windows App window after connecting", isOn: $minimizesMainWindow)
                    if minimizesMainWindow {
                        LabeledContent("Accessibility access") {
                            if isAccessibilityTrusted {
                                Label("Allowed", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Button("Open System Settings…") {
                                    WindowsAppWindowMinimizer.requestAccess()
                                    WindowsAppWindowMinimizer.openAccessibilitySettings()
                                }
                            }
                        }
                    }
                } footer: {
                    Text("CoreRemote needs Accessibility access to minimize another app's window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            RDPDefaultsSection()

            Section {
                KeyboardShortcuts.Recorder("Quick connect", name: .quickConnect)
            } footer: {
                Text("Opens a search box from any app: type a name, host or user and press Return to connect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Shortcuts and Spotlight") {
                    Button("Open Shortcuts", systemImage: "square.2.layers.3d", action: ShortcutsApp.open)
                }
            } footer: {
                Text("Search a connection's name in Spotlight to connect. In the Shortcuts app, add CoreRemote's \"Connect\" action to a new shortcut and pick a connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show in menu bar", isOn: $showsMenuBarIcon)
            } footer: {
                Text("Connect to favorites, recent connections and groups from the menu bar. CoreRemote keeps running there after you close its window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show server status", isOn: $checksReachability)
            } footer: {
                Text("While the window is open, CoreRemote tries each server's port every minute and shows a green or red dot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Recent connections") {
                    Button("Clear History…") { confirmsClearHistory = true }
                        .disabled(!hasHistory)
                }
            } footer: {
                Text("Removes the Recent list and last-connected times. Connections aren't deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Clear connection history?", isPresented: $confirmsClearHistory) {
            Button("Clear History", role: .destructive) {
                try? Connection.clearHistory(in: modelContext)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            // Access and installs can change while Settings is open.
            while !Task.isCancelled {
                isAccessibilityTrusted = WindowsAppWindowMinimizer.isTrusted
                installed = Set(RDPClient.allCases.filter(\.isInstalled))
                installedTerminals = Set(TerminalApp.allCases.filter(\.isInstalled))
                fileTransferApps = FileTransferApp.installed
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
