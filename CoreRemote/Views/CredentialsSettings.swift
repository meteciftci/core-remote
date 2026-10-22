import AppKit
import SwiftData
import SwiftUI

/// Settings › Credentials: profiles that several connections can log in with.
struct CredentialsSettings: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CredentialProfile.name) private var profiles: [CredentialProfile]
    @State private var selection: UUID?
    @State private var editing: ProfileEditorTarget?
    @State private var pendingDeletion: CredentialProfile?
    @State private var errorMessage: String?

    private var selectedProfile: CredentialProfile? {
        selection.flatMap { id in profiles.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if profiles.isEmpty {
                    ContentUnavailableView {
                        Label("No Profiles", systemImage: "person.badge.key")
                    } description: {
                        Text("A profile keeps one user name and password, such as a domain account, for several connections. Change the password here once and every connection uses the new one.")
                    } actions: {
                        Button("Add Profile") { editing = .new }
                    }
                } else {
                    List(selection: $selection) {
                        ForEach(profiles) { profile in
                            ProfileRow(profile: profile)
                                .tag(profile.id)
                        }
                    }
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        if let profile = ids.first.flatMap({ id in profiles.first { $0.id == id } }) {
                            Button("Edit…") { editing = .existing(profile) }
                            Button("Delete…", role: .destructive) { requestDeletion(of: profile) }
                        }
                    } primaryAction: { ids in
                        if let profile = ids.first.flatMap({ id in profiles.first { $0.id == id } }) {
                            editing = .existing(profile)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack(spacing: 0) {
                Button("Add Profile", systemImage: "plus") { editing = .new }
                Button("Delete Profile", systemImage: "minus") {
                    if let selectedProfile { requestDeletion(of: selectedProfile) }
                }
                .disabled(selectedProfile == nil)
                Spacer()
                Button("Edit…") {
                    if let selectedProfile { editing = .existing(selectedProfile) }
                }
                .disabled(selectedProfile == nil)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(8)
        }
        .frame(width: 480, height: 360)
        .sheet(item: $editing) { target in
            ProfileEditor(target: target)
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { profile in
            Button("Delete Profile", role: .destructive) { delete(profile) }
        } message: { profile in
            Text("\(profile.connections.count) connections use it. They keep its user name, but their password has to be entered again.")
        }
        .alert("Couldn't Delete the Profile", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var deletionTitle: String {
        String(localized: "Delete “\(pendingDeletion?.name ?? "")”?")
    }

    private func requestDeletion(of profile: CredentialProfile) {
        if profile.connections.isEmpty {
            delete(profile)
        } else {
            pendingDeletion = profile
        }
    }

    private func delete(_ profile: CredentialProfile) {
        do {
            try CredentialProfile.delete(profile, in: modelContext, passwords: KeychainPasswordStore.shared)
            selection = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProfileRow: View {
    let profile: CredentialProfile

    var body: some View {
        HStack {
            Image(systemName: "person.badge.key.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading) {
                Text(verbatim: profile.name)
                Text(verbatim: profile.username)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(profile.connections.count) connections")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

enum ProfileEditorTarget: Identifiable {
    case new
    case existing(CredentialProfile)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let profile): profile.id.uuidString
        }
    }
}

/// Adds or edits a profile in a sheet.
private struct ProfileEditor: View {
    let target: ProfileEditorTarget

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var username = ""
    @State private var password = ""
    @State private var keyFilePath = ""
    @State private var errorMessage: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !trimmedName.isEmpty && !trimmedUsername.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Domain account"))
                    TextField("Username", text: $username, prompt: Text("Required"))
                        .textContentType(.username)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password, prompt: Text("Optional"))
                        .textContentType(.password)
                    LabeledContent("Key File") {
                        HStack {
                            Text(keyFilePath.isEmpty ? String(localized: "None") : (keyFilePath as NSString).abbreviatingWithTildeInPath)
                                .foregroundStyle(keyFilePath.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if !keyFilePath.isEmpty {
                                Button("Clear", systemImage: "xmark.circle.fill") { keyFilePath = "" }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                            }
                            Button("Choose…", action: chooseKeyFile)
                        }
                    }
                } footer: {
                    Text("The password is kept in your Keychain. The key file is used by SSH connections only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
        .onAppear(perform: load)
    }

    private func load() {
        guard case .existing(let profile) = target else { return }
        name = profile.name
        username = profile.username
        keyFilePath = profile.keyFilePath ?? ""
        password = KeychainPasswordStore.shared.password(for: profile.id) ?? ""
    }

    private func save() {
        guard isValid else { return }
        let profile: CredentialProfile
        switch target {
        case .new: profile = CredentialProfile(name: "", username: "")
        case .existing(let existing): profile = existing
        }
        do {
            try KeychainPasswordStore.shared.setPassword(password, for: profile.id)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        profile.name = trimmedName
        profile.username = trimmedUsername
        let key = keyFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.keyFilePath = key.isEmpty ? nil : key
        if case .new = target {
            modelContext.insert(profile)
        }
        try? modelContext.save()
        dismiss()
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
            keyFilePath = url.path
        }
    }
}
