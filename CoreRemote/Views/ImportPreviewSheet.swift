import SwiftData
import SwiftUI

/// Lists what was found in `~/.ssh/config` or `.rdp` files so the user can pick what to add.
/// Connections that already exist (same host, port and user) start unchecked.
struct ImportPreviewSheet: View {
    var title: String
    var candidates: [ImportCandidate]
    var onImported: (Int) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [Connection]
    @Query(sort: \ConnectionGroup.name) private var groups: [ConnectionGroup]

    @State private var selection = Set<UUID>()
    @State private var duplicates = Set<UUID>()
    @State private var groupID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: "square.and.arrow.down.on.square")
                .font(.title2.weight(.semibold))
            Text("Choose the connections to add. Ones that already exist are unchecked.")
                .foregroundStyle(.secondary)

            List {
                ForEach(candidates) { candidate in
                    Toggle(isOn: binding(for: candidate)) {
                        HStack(spacing: 10) {
                            TypeBadge(type: candidate.type, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.name)
                                    .font(.body.weight(.medium))
                                Text(ImportCandidate.duplicateKey(host: candidate.host, port: candidate.port, username: candidate.username))
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            if duplicates.contains(candidate.id) {
                                Text("Already exists")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if candidate.username.isEmpty {
                                Text("No username")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .frame(minHeight: 260)

            HStack {
                Button("Select All") { selection = Set(candidates.map(\.id)) }
                Button("Select None") { selection = [] }
                Spacer()
                Picker("Add to group", selection: $groupID) {
                    Text("None").tag(UUID?.none)
                    ForEach(groups) { group in
                        Text(verbatim: group.name).tag(UUID?.some(group.id))
                    }
                }
                .fixedSize()
            }
            .controlSize(.small)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import \(selection.count)") { importSelected() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(selection.isEmpty)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            duplicates = ConnectionImporter.duplicateIDs(in: candidates, existing: existing)
            selection = Set(candidates.map(\.id)).subtracting(duplicates)
        }
    }

    private func binding(for candidate: ImportCandidate) -> Binding<Bool> {
        Binding(
            get: { selection.contains(candidate.id) },
            set: { isOn in
                if isOn { selection.insert(candidate.id) } else { selection.remove(candidate.id) }
            }
        )
    }

    private func importSelected() {
        let chosen = candidates.filter { selection.contains($0.id) }
        do {
            try ConnectionImporter.add(chosen, to: groups.first { $0.id == groupID }, in: modelContext)
            onImported(chosen.count)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
