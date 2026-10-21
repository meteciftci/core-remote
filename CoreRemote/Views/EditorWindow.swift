import SwiftData
import SwiftUI

/// What an editor window edits. Windows for the same connection are reused;
/// every "New Connection" gets its own window.
struct EditorTarget: Codable, Hashable {
    var connectionID: UUID?
    var defaultGroupID: UUID?
    var newWindowID: UUID?

    static func edit(_ connection: Connection) -> EditorTarget {
        EditorTarget(connectionID: connection.id)
    }

    static func new(in groupID: UUID?) -> EditorTarget {
        EditorTarget(defaultGroupID: groupID, newWindowID: UUID())
    }
}

enum EditorWindow {
    static let id = "editor"
}

/// Hosts `ConnectionEditor` in its own movable window.
struct EditorWindowContent: View {
    var target: EditorTarget?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let target, let connection = connection(for: target) {
            ConnectionEditor(connection: connection, defaultGroupID: target.defaultGroupID)
        } else if let target, target.connectionID == nil {
            ConnectionEditor(connection: nil, defaultGroupID: target.defaultGroupID)
        } else {
            // The connection was deleted, or the window came back without a target.
            Color.clear
                .frame(width: 1, height: 1)
                .onAppear { dismiss() }
        }
    }

    private func connection(for target: EditorTarget) -> Connection? {
        guard let id = target.connectionID else { return nil }
        return try? modelContext.fetch(FetchDescriptor<Connection>(predicate: #Predicate { $0.id == id })).first
    }
}
