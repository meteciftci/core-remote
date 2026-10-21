import AppKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(RDPClient.storageKey) private var rdpClient: RDPClient = RDPClient.defaultClient
    @AppStorage(WindowsApp.minimizeStorageKey) private var minimizesMainWindow = true
    @State private var isAccessibilityTrusted = WindowsAppWindowMinimizer.isTrusted
    @State private var installed: Set<RDPClient> = []
    @State private var confirmsClearHistory = false
    @AppStorage(MenuBarContent.visibilityKey) private var showsMenuBarIcon = true

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Connection> { $0.lastConnectedAt != nil }) private var recentConnections: [Connection]

    private var hasHistory: Bool { !recentConnections.isEmpty }

    var body: some View {
        Form {
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

            Section {
                Toggle("Show in menu bar", isOn: $showsMenuBarIcon)
            } footer: {
                Text("Connect to favorites, recent connections and groups from the menu bar. CoreRemote keeps running there after you close its window.")
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
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
