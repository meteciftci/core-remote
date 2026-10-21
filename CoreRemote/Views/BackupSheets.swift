import SwiftUI
import UniformTypeIdentifiers

nonisolated struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.coreRemoteBackup, .json]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Export options, shown before the save panel.
struct ExportSheet: View {
    var connectionCount: Int
    var onExport: (_ passphrase: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var includePasswords = false
    @State private var passphrase = ""
    @State private var confirmation = ""

    private var isValid: Bool {
        !includePasswords || (passphrase.count >= 8 && passphrase == confirmation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Export Connections", systemImage: "square.and.arrow.up")
                .font(.title2.weight(.semibold))
            Text("\(connectionCount) connections and all groups will be saved to a .coreremote file.")
                .foregroundStyle(.secondary)

            Form {
                Toggle("Include passwords", isOn: $includePasswords.animation())
                if includePasswords {
                    SecureField("Passphrase", text: $passphrase, prompt: Text("At least 8 characters"))
                    SecureField("Confirm", text: $confirmation)
                    if !confirmation.isEmpty, passphrase != confirmation {
                        Text("Passphrases don't match.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Text(includePasswords
                 ? "The file is encrypted with your passphrase. Without it the backup can't be opened."
                 : "Passwords are not included. The file is not encrypted.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    onExport(includePasswords ? passphrase : nil)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(!isValid)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Asks for the passphrase of an encrypted backup.
struct ImportPassphraseSheet: View {
    var errorMessage: String?
    var onSubmit: (String) -> Void
    var onCancel: () -> Void

    @State private var passphrase = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Encrypted Backup", systemImage: "lock.doc")
                .font(.title2.weight(.semibold))
            Text("Enter the passphrase used when this backup was exported.")
                .foregroundStyle(.secondary)
            SecureField("Passphrase", text: $passphrase)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSubmit(passphrase) }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Import") { onSubmit(passphrase) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(passphrase.isEmpty)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 400)
    }
}
