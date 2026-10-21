#if DEBUG
import Foundation
import SwiftData

/// Sample connections for screenshots. Launch a Debug build with `-DemoData` to use an
/// in-memory store filled with these; `-DemoEditor`, `-DemoSettings` or `-DemoQuickConnect`
/// also opens that screen.
enum DemoData {
    static var isEnabled: Bool { arguments.contains("-DemoData") }
    static var opensEditor: Bool { arguments.contains("-DemoEditor") }
    static var opensSettings: Bool { arguments.contains("-DemoSettings") }
    static var opensQuickConnect: Bool { arguments.contains("-DemoQuickConnect") }

    static let editorConnectionName = "File Server"

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// Made-up server status, since the demo hosts don't exist.
    static func reachability(for host: String) -> ReachabilityMonitor.Status {
        switch host {
        case "db-01.example.com": .unreachable(reason: String(localized: "Connection refused"))
        case "192.0.2.15": .unreachable(reason: String(localized: "Timed out"))
        default: .reachable(latency: .milliseconds(host.count * 3))
        }
    }

    static func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: Connection.self, ConnectionGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        insert(into: container.mainContext)
        return container
    }

    private static func insert(into context: ModelContext) {
        let production = ConnectionGroup(name: "Production")
        let lab = ConnectionGroup(name: "Lab")
        context.insert(production)
        context.insert(lab)

        let connections = [
            Connection(name: "Web Server", host: "web-01.example.com", type: .ssh, username: "deploy",
                       isFavorite: true, group: production),
            Connection(name: "Database", host: "db-01.example.com", type: .ssh, port: 2222, username: "postgres",
                       group: production),
            Connection(name: "File Server", host: "fs-01.example.com", type: .rdp, username: "EXAMPLE\\admin",
                       isFavorite: true, group: production),
            Connection(name: "Build Agent", host: "10.0.0.42", type: .ssh, username: "ci",
                       keyFilePath: "~/.ssh/id_ed25519", group: lab),
            Connection(name: "Windows Desktop", host: "192.0.2.15", type: .rdp, username: "alice", group: lab),
            Connection(name: "Raspberry Pi", host: "raspberrypi.local", type: .ssh, username: "pi"),
        ]
        connections.forEach(context.insert)
        connections[0].lastConnectedAt = .now.addingTimeInterval(-5 * 60)
        connections[2].lastConnectedAt = .now.addingTimeInterval(-2 * 3600)
        connections[3].lastConnectedAt = .now.addingTimeInterval(-26 * 3600)
        try? context.save()
    }
}
#endif
