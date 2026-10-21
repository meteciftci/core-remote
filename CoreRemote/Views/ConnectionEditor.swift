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

    @State private var draft = ConnectionDraft()
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case name, host }

    private var typeBinding: Binding<ConnectionType> {
        Binding(get: { draft.type }, set: { draft.setType($0) })
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
                    TextField("Username", text: $draft.username, prompt: Text("Required"))
                        .textContentType(.username)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $draft.password, prompt: Text("Optional"))
                        .textContentType(.password)
                    if draft.type == .ssh {
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
                    Text(draft.type == .ssh
                         ? "The password is kept in your Keychain and entered for you when ssh asks."
                         : "The password is kept in your Keychain and copied to the clipboard for 30 seconds when you connect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Group", selection: $draft.groupID) {
                        Text("None").tag(UUID?.none)
                        if !groups.isEmpty { Divider() }
                        ForEach(groups) { group in
                            Text(verbatim: group.name).tag(UUID?.some(group.id))
                        }
                    }
                    Toggle("Favorite", isOn: $draft.isFavorite)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }

            HStack {
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
            try KeychainPasswordStore.shared.setPassword(draft.password, for: target.id)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        draft.apply(to: target, group: groups.first { $0.id == draft.groupID })
        if connection == nil {
            modelContext.insert(target)
        }
        try? modelContext.save()
        dismiss()
    }
}
