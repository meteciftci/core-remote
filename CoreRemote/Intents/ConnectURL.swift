import AppKit
import Foundation
import SwiftData

/// `coreremote://connect/<connection id>` opens a saved connection, for links and scripts.
enum ConnectURL {
    nonisolated static let scheme = "coreremote"

    nonisolated static func url(for id: UUID) -> URL {
        URL(string: "\(scheme)://connect/\(id.uuidString)")!
    }

    nonisolated static func connectionID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == "connect" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    /// Connects to the connection a URL names. Problems show in a standalone alert,
    /// since a URL can arrive while no window is open.
    static func handle(_ url: URL, container: ModelContainer, launcher: ConnectionLauncher) async {
        guard let id = connectionID(from: url) else { return }
        let descriptor = FetchDescriptor<Connection>(predicate: #Predicate { $0.id == id })
        guard let connection = try? container.mainContext.fetch(descriptor).first else {
            LaunchProblemAlert.run(.failed(name: "", message: String(localized: "This connection no longer exists.")), launcher: launcher)
            return
        }
        await launcher.open(connection)
        if let problem = launcher.launchProblem {
            launcher.launchProblem = nil
            LaunchProblemAlert.run(problem, launcher: launcher)
        }
    }
}

enum ShortcutsApp {
    /// Opens Kestirmeler (Shortcuts), where CoreRemote lists a "Connect to <name>" shortcut per connection.
    static func open() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
