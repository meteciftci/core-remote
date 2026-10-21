import AppKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var connections: [Connection]
    @Query(sort: \ConnectionGroup.name) private var groups: [ConnectionGroup]

    @State private var launcher = ConnectionLauncher()
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var editor: EditorRequest?
    @State private var alert: AlertContent?
    @State private var showsWindowsAppMissing = false

    @State private var groupNameRequest: GroupNameRequest?
    @State private var groupName = ""

    @State private var showsExportOptions = false
    @State private var exportDocument: BackupDocument?
    @State private var showsImporter = false
    @State private var pendingImport: PendingImport?

    private var filter: SidebarItem { sidebarSelection ?? .all }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $sidebarSelection,
                onNewGroup: { requestGroupName(for: nil) },
                onRenameGroup: { requestGroupName(for: $0) }
            )
        } detail: {
            ConnectionListView(
                filter: filter,
                title: title(for: filter),
                onConnect: connect,
                onEdit: { editor = EditorRequest(connection: $0) },
                onCopyCommand: launcher.copySSHCommand
            )
            .id(filter)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Import…", systemImage: "square.and.arrow.down") { showsImporter = true }
                        Button("Export…", systemImage: "square.and.arrow.up") { showsExportOptions = true }
                            .disabled(connections.isEmpty)
                    } label: {
                        Label("Backup", systemImage: "arrow.up.arrow.down.circle")
                    }
                    .help("Import or export connections")
                }
            }
        }
        .overlay(alignment: .bottom) { toast }
        .focusedSceneValue(\.appActions, AppActions(
            newConnection: { editor = EditorRequest(connection: nil) },
            newGroup: { requestGroupName(for: nil) },
            importBackup: { showsImporter = true },
            exportBackup: { if !connections.isEmpty { showsExportOptions = true } }
        ))
        .sheet(item: $editor) { request in
            ConnectionEditor(connection: request.connection, defaultGroupID: currentGroupID)
        }
        .sheet(isPresented: $showsExportOptions) {
            ExportSheet(connectionCount: connections.count, onExport: export)
        }
        .sheet(item: $pendingImport) { pending in
            ImportPassphraseSheet(
                errorMessage: pending.errorMessage,
                onSubmit: { finishImport(pending.data, passphrase: $0) },
                onCancel: { pendingImport = nil }
            )
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .coreRemoteBackup,
            defaultFilename: "CoreRemote Backup"
        ) { result in
            if case .failure(let error) = result {
                alert = AlertContent(title: String(localized: "Export Failed"), message: error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.coreRemoteBackup, .json]) { result in
            switch result {
            case .success(let url): startImport(from: url)
            case .failure(let error): alert = AlertContent(title: String(localized: "Import Failed"), message: error.localizedDescription)
            }
        }
        .alert(groupNameRequest?.title ?? "", isPresented: Binding(get: { groupNameRequest != nil }, set: { if !$0 { groupNameRequest = nil } })) {
            TextField("Group name", text: $groupName)
            Button("Cancel", role: .cancel) {}
            Button("Save", action: saveGroupName)
                .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .alert(alert?.title ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("OK") {}
        } message: {
            Text(alert?.message ?? "")
        }
        .alert("Windows App is required", isPresented: $showsWindowsAppMissing) {
            Button("Open App Store") { openURL(WindowsApp.appStoreURL) }
            Button("Copy brew Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(WindowsApp.brewCommand, forType: .string)
                launcher.show(String(localized: "Command copied"))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RDP connections open in Microsoft Windows App. Install it from the App Store, or with Homebrew:\n\n\(WindowsApp.brewCommand)")
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toast: some View {
        if let notice = launcher.notice {
            Label(notice, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Connecting

    private func connect(_ connection: Connection) {
        Task {
            do {
                try await launcher.connect(connection)
            } catch LaunchError.windowsAppMissing {
                showsWindowsAppMissing = true
            } catch {
                alert = AlertContent(
                    title: String(localized: "Couldn't connect to “\(connection.name)”"),
                    message: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Groups

    private var currentGroupID: UUID? {
        if case .group(let id) = filter { id } else { nil }
    }

    private func title(for item: SidebarItem) -> String {
        switch item {
        case .all: String(localized: "All Connections")
        case .favorites: String(localized: "Favorites")
        case .type(let type): type.title
        case .group(let id): groups.first { $0.id == id }?.name ?? String(localized: "Group")
        }
    }

    private func requestGroupName(for group: ConnectionGroup?) {
        groupName = group?.name ?? ""
        groupNameRequest = GroupNameRequest(group: group)
    }

    private func saveGroupName() {
        let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let group = groupNameRequest?.group {
            group.name = name
        } else {
            let group = ConnectionGroup(name: name)
            modelContext.insert(group)
            sidebarSelection = .group(group.id)
        }
        try? modelContext.save()
        groupNameRequest = nil
    }

    // MARK: - Backup

    private func export(passphrase: String?) {
        let payload = BackupStore.payload(
            connections: connections,
            groups: groups,
            includePasswords: passphrase != nil,
            passwords: KeychainPasswordStore.shared
        )
        Task {
            do {
                let data = try await Task.detached { try Backup.encode(payload, passphrase: passphrase) }.value
                exportDocument = BackupDocument(data: data)
            } catch {
                alert = AlertContent(title: String(localized: "Export Failed"), message: error.localizedDescription)
            }
        }
    }

    private func startImport(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            if try Backup.isEncrypted(data) {
                pendingImport = PendingImport(data: data)
            } else {
                finishImport(data, passphrase: nil)
            }
        } catch {
            alert = AlertContent(title: String(localized: "Import Failed"), message: error.localizedDescription)
        }
    }

    private func finishImport(_ data: Data, passphrase: String?) {
        Task {
            do {
                let payload = try await Task.detached { try Backup.decode(data, passphrase: passphrase) }.value
                let summary = try BackupStore.importPayload(payload, into: modelContext, passwords: KeychainPasswordStore.shared)
                pendingImport = nil
                alert = AlertContent(
                    title: String(localized: "Import Complete"),
                    message: String(localized: "\(summary.added) added, \(summary.skipped) skipped (already present), \(summary.groupsCreated) new groups.")
                )
            } catch BackupError.wrongPassphrase {
                pendingImport = PendingImport(data: data, errorMessage: BackupError.wrongPassphrase.localizedDescription)
            } catch {
                pendingImport = nil
                alert = AlertContent(title: String(localized: "Import Failed"), message: error.localizedDescription)
            }
        }
    }
}

private struct EditorRequest: Identifiable {
    let id = UUID()
    var connection: Connection?
}

private struct GroupNameRequest {
    var group: ConnectionGroup?

    var title: String {
        group == nil ? String(localized: "New Group") : String(localized: "Rename Group")
    }
}

private struct AlertContent {
    var title: String
    var message: String
}

private struct PendingImport: Identifiable {
    let id = UUID()
    var data: Data
    var errorMessage: String?
}
