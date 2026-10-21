import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Query private var connections: [Connection]
    @Query(sort: \ConnectionGroup.name) private var groups: [ConnectionGroup]

    @Environment(ConnectionLauncher.self) private var launcher
    @State private var reachability = ReachabilityMonitor()
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var alert: AlertContent?
    @State private var missingClient: RDPClient?

    @State private var groupNameRequest: GroupNameRequest?
    @State private var groupName = ""

    @State private var showsExportOptions = false
    @State private var exportDocument: BackupDocument?
    @State private var showsImporter = false
    @State private var pendingImport: PendingImport?
    @State private var importPreview: ImportPreview?

    private var filter: SidebarItem { sidebarSelection ?? .all }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $sidebarSelection,
                onRenameGroup: { requestGroupName(for: $0) }
            )
        } detail: {
            ConnectionListView(
                filter: filter,
                title: title(for: filter),
                onConnect: { connection in Task { await launcher.open(connection) } },
                onEdit: openEditor,
                onNewGroup: { requestGroupName(for: nil) },
                onCopyCommand: launcher.copySSHCommand,
                onImport: { showsImporter = true },
                onExport: { showsExportOptions = true },
                onImportSSHConfig: importSSHConfig,
                onImportRDPFiles: chooseRDPFiles
            )
            .id(filter)
            .environment(reachability)
        }
        .overlay(alignment: .bottom) { toast }
        .modifier(ReachabilityRefresh(monitor: reachability, connections: connections))
        // Launches from the menu bar report here too, so this also runs when the window opens.
        .onChange(of: launcher.launchProblem, initial: true) {
            guard let problem = launcher.launchProblem else { return }
            switch problem {
            case .missingClient(let client):
                missingClient = client
            case .failed(let name, let message):
                alert = AlertContent(title: String(localized: "Couldn't connect to “\(name)”"), message: message)
            }
            launcher.launchProblem = nil
        }
        .task {
            #if DEBUG
            if DemoData.opensEditor {
                openEditor(connections.first { $0.name == DemoData.editorConnectionName })
            }
            if DemoData.opensSettings {
                openSettings()
            }
            if DemoData.opensImport {
                showPreview(title: String(localized: "Import from SSH Config"), candidates: SSHConfigParser.parse(DemoData.sshConfig), emptyMessage: "")
            }
            if DemoData.opensQuickConnect {
                // Wait until the main window has taken focus, or the panel closes right away.
                try? await Task.sleep(for: .seconds(1))
                QuickConnectPanel.shared.show()
            }
            #endif
        }
        .focusedSceneValue(\.appActions, AppActions(
            newConnection: { openEditor(nil) },
            newGroup: { requestGroupName(for: nil) },
            importBackup: { showsImporter = true },
            importSSHConfig: importSSHConfig,
            importRDPFiles: chooseRDPFiles,
            exportBackup: { if !connections.isEmpty { showsExportOptions = true } }
        ))
        .sheet(item: $importPreview) { preview in
            ImportPreviewSheet(title: preview.title, candidates: preview.candidates) { count in
                launcher.show(String(localized: "\(count) connections imported"))
            }
        }
        // Drop .rdp files anywhere on the window to import them.
        .dropDestination(for: URL.self) { urls, _ in
            let rdpFiles = urls.filter { $0.pathExtension.lowercased() == "rdp" }
            guard !rdpFiles.isEmpty else { return false }
            importRDPFiles(rdpFiles)
            return true
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
        .alert(
            String(localized: "\(missingClient?.title ?? "") is required"),
            isPresented: Binding(get: { missingClient != nil }, set: { if !$0 { missingClient = nil } }),
            presenting: missingClient
        ) { client in
            if client == .windowsApp {
                Button("Open App Store") { openURL(WindowsApp.appStoreURL) }
            }
            Button("Copy brew Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(client.brewCommand, forType: .string)
                launcher.show(String(localized: "Command copied"))
            }
            Button("Cancel", role: .cancel) {}
        } message: { client in
            switch client {
            case .windowsApp:
                Text("RDP connections open in Microsoft Windows App. Install it from the App Store, or with Homebrew:\n\n\(client.brewCommand)")
            case .freeRDP:
                Text("RDP connections are set to open in FreeRDP. Install it with Homebrew, or choose Windows App in Settings:\n\n\(client.brewCommand)")
            }
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

    // MARK: - Editor

    /// Opens the editor in its own window; `nil` creates a connection in the selected group.
    private func openEditor(_ connection: Connection?) {
        openWindow(id: EditorWindow.id, value: connection.map(EditorTarget.edit) ?? .new(in: currentGroupID))
    }

    // MARK: - Groups

    private var currentGroupID: UUID? {
        if case .group(let id) = filter { id } else { nil }
    }

    private func title(for item: SidebarItem) -> String {
        switch item {
        case .all: String(localized: "All Connections")
        case .favorites: String(localized: "Favorites")
        case .recent: String(localized: "Recent")
        case .type(let type): type.title
        case .group(let id): groups.first { $0.id == id }?.name ?? String(localized: "Group")
        case .tag(let tag): "#\(tag)"
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

    // MARK: - Importing other formats

    private func importSSHConfig() {
        let url = SSHConfigParser.defaultURL
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            alert = AlertContent(
                title: String(localized: "No SSH Config Found"),
                message: String(localized: "CoreRemote looks for ~/.ssh/config, which doesn't exist or can't be read.")
            )
            return
        }
        showPreview(
            title: String(localized: "Import from SSH Config"),
            candidates: SSHConfigParser.parse(text),
            emptyMessage: String(localized: "~/.ssh/config has no Host entries to import. Entries with wildcards are skipped.")
        )
    }

    private func chooseRDPFiles() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import .rdp Files")
        panel.allowedContentTypes = [UTType(filenameExtension: "rdp") ?? .data]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            importRDPFiles(panel.urls)
        }
    }

    private func importRDPFiles(_ urls: [URL]) {
        let candidates = urls.compactMap { url -> ImportCandidate? in
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return RDPFileParser.parse(data, name: url.deletingPathExtension().lastPathComponent)
        }
        showPreview(
            title: String(localized: "Import .rdp Files"),
            candidates: candidates,
            emptyMessage: String(localized: "None of the selected files has a server address.")
        )
    }

    private func showPreview(title: String, candidates: [ImportCandidate], emptyMessage: String) {
        guard !candidates.isEmpty else {
            alert = AlertContent(title: String(localized: "Nothing to Import"), message: emptyMessage)
            return
        }
        importPreview = ImportPreview(title: title, candidates: candidates)
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

private struct ImportPreview: Identifiable {
    let id = UUID()
    var title: String
    var candidates: [ImportCandidate]
}

private struct PendingImport: Identifiable {
    let id = UUID()
    var data: Data
    var errorMessage: String?
}
