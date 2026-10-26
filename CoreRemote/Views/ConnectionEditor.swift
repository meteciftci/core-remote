import AppKit
import SwiftData
import SwiftUI

struct ConnectionEditor: View {
    /// `nil` creates a new connection.
    var connection: Connection?
    var defaultGroupID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ConnectionGroup.name) private var groups: [ConnectionGroup]
    @Query(sort: \CredentialProfile.name) private var profiles: [CredentialProfile]

    private var selectedProfile: CredentialProfile? {
        draft.credentialProfileID.flatMap { id in profiles.first { $0.id == id } }
    }

    @State private var draft = ConnectionDraft()
    @State private var errorMessage: String?
    @State private var showsNewGroup = false
    @State private var newGroupName = ""
    @FocusState private var focusedField: Field?

    private enum Field { case name, host }

    /// Picker tag for the "New Group…" item; choosing it asks for a name instead of selecting.
    private static let newGroupTag = UUID()

    private var typeBinding: Binding<ConnectionType> {
        Binding(get: { draft.type }, set: { draft.setType($0) })
    }

    private var groupBinding: Binding<UUID?> {
        Binding(
            get: { draft.groupID },
            set: { id in
                if id == Self.newGroupTag {
                    newGroupName = ""
                    showsNewGroup = true
                } else {
                    draft.groupID = id
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TypeBadge(type: draft.type, size: 40)
                    .animation(.smooth, value: draft.type)
                Text(connection == nil ? "New Connection" : "Edit Connection")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding([.horizontal, .top], 20)

            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Production server"))
                        .focused($focusedField, equals: .name)
                    Picker("Type", selection: typeBinding) {
                        ForEach(ConnectionType.allCases) { type in
                            Text(verbatim: type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if draft.type.usesNetwork {
                    Section {
                        TextField("Host", text: $draft.host, prompt: Text("192.168.1.10 or server.example.com"))
                            .focused($focusedField, equals: .host)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                        TextField("Port", value: $draft.port, format: .number.grouping(.never), prompt: Text(verbatim: "\(draft.type.defaultPort)"))
                        if draft.port != nil, !draft.isPortValid {
                            Text("Port must be between 1 and 65535.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Server")
                    }

                    Section {
                        Picker("Credentials", selection: $draft.credentialProfileID) {
                            Text("This connection only").tag(UUID?.none)
                            if !profiles.isEmpty { Divider() }
                            ForEach(profiles) { profile in
                                Text(verbatim: profile.name).tag(UUID?.some(profile.id))
                            }
                        }
                        if let profile = selectedProfile {
                            LabeledContent("Username", value: profile.username)
                            if draft.type == .ssh, let key = profile.keyFilePath {
                                LabeledContent("Key File", value: (key as NSString).abbreviatingWithTildeInPath)
                            }
                        } else {
                            TextField("Username", text: $draft.username, prompt: Text("Required"))
                                .textContentType(.username)
                                .autocorrectionDisabled()
                            SecureField("Password", text: $draft.password, prompt: Text("Optional"))
                                .textContentType(.password)
                        }
                        if draft.type == .rdp {
                            Toggle("Ignore certificate warnings", isOn: $draft.ignoreCertificateErrors)
                        } else if selectedProfile == nil {
                            LabeledContent("Key File") {
                                HStack {
                                    Text(draft.keyFilePath.isEmpty ? String(localized: "None") : (draft.keyFilePath as NSString).abbreviatingWithTildeInPath)
                                        .foregroundStyle(draft.keyFilePath.isEmpty ? .secondary : .primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    if !draft.keyFilePath.isEmpty {
                                        Button("Clear", systemImage: "xmark.circle.fill") { draft.keyFilePath = "" }
                                            .labelStyle(.iconOnly)
                                            .buttonStyle(.borderless)
                                    }
                                    Button("Choose…", action: chooseKeyFile)
                                }
                            }
                        }
                    } header: {
                        Text("Authentication")
                    } footer: {
                        Text(selectedProfile != nil
                             ? "The profile's user name and password are used. Change them in Settings > Credentials."
                             : draft.type == .ssh
                             ? "The password is kept in your Keychain and entered for you when ssh asks."
                             : RDPClient.current == .freeRDP
                             ? "The password is kept in your Keychain and passed to FreeRDP when you connect."
                             : "The password is kept in your Keychain and copied to the clipboard for 30 seconds when you connect.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    SerialSection(device: $draft.host, options: $draft.serial)
                }

                if draft.type == .rdp {
                    RDPOverridesSection(overrides: $draft.rdp)
                }

                Section {
                    Picker("Group", selection: groupBinding) {
                        Text("None").tag(UUID?.none)
                        if !groups.isEmpty { Divider() }
                        ForEach(groups) { group in
                            Text(verbatim: group.name).tag(UUID?.some(group.id))
                        }
                        Divider()
                        Text("New Group…").tag(UUID?.some(Self.newGroupTag))
                    }
                    Toggle("Favorite", isOn: $draft.isFavorite)
                    TextField("Tags", text: $draft.tagsText, prompt: Text("prod, linux, dc"))
                        .autocorrectionDisabled()
                } footer: {
                    Text("Separate tags with commas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Notes") {
                    TextField("Notes", text: $draft.notes, prompt: Text("Optional"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            // A Form in a sheet otherwise collapses to a few rows.
            .frame(minHeight: 680, idealHeight: 680)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }

            HStack {
                if connection != nil {
                    // Every connection already has a "Connect to <name>" shortcut there.
                    Button("Open Shortcuts", systemImage: "square.2.layers.3d", action: ShortcutsApp.open)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(!draft.isValid)
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 480)
        .onAppear(perform: load)
        .alert("New Group", isPresented: $showsNewGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Cancel", role: .cancel) {}
            Button("Save", action: createGroup)
                .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func createGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let existing = groups.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            draft.groupID = existing.id
            return
        }
        let group = ConnectionGroup(name: name)
        modelContext.insert(group)
        try? modelContext.save()
        draft.groupID = group.id
    }

    private func load() {
        if let connection {
            draft = ConnectionDraft(connection: connection, password: KeychainPasswordStore.shared.password(for: connection.id))
        } else {
            draft.groupID = defaultGroupID
        }
        focusedField = .name
    }

    private func chooseKeyFile() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose SSH Key")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh")
        if panel.runModal() == .OK, let url = panel.url {
            draft.keyFilePath = url.path
        }
    }

    private func save() {
        guard draft.isValid else { return }
        let target = connection ?? Connection(name: "", host: "", type: draft.type, username: "")
        do {
            try KeychainPasswordStore.shared.setPassword(draft.ownPassword, for: target.id)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        draft.apply(to: target, group: groups.first { $0.id == draft.groupID }, profile: selectedProfile)
        if connection == nil {
            target.sortIndex = ConnectionOrder.nextIndex(in: modelContext)
            modelContext.insert(target)
        }
        try? modelContext.save()
        dismiss()
    }
}
