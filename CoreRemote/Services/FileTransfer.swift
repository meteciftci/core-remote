import AppKit
import Foundation

/// Where "File Transfer" opens an SSH connection.
nonisolated enum FileTransferClient: Hashable, Sendable {
    /// The Mac's default app for `sftp://` links when it's a file transfer app, otherwise `sftp`.
    case automatic
    /// `sftp` in the SSH terminal, with the saved password entered automatically.
    case terminal
    /// A file transfer app such as Cyberduck, Transmit or ForkLift, by bundle identifier.
    case app(String)

    static let storageKey = "fileTransferClient"
    private static let terminalValue = "terminal"

    init(storedValue: String) {
        self = switch storedValue {
        case "": .automatic
        case Self.terminalValue: .terminal
        default: .app(storedValue)
        }
    }

    var storedValue: String {
        switch self {
        case .automatic: ""
        case .terminal: Self.terminalValue
        case .app(let bundleIdentifier): bundleIdentifier
        }
    }

    static var selected: FileTransferClient {
        FileTransferClient(storedValue: UserDefaults.standard.string(forKey: storageKey) ?? "")
    }
}

/// An installed app that opens `sftp://` links, other than a terminal.
struct FileTransferApp: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String
    let url: URL

    var id: String { bundleIdentifier }

    /// Terminal opens `sftp://` links too; CoreRemote runs `sftp` itself instead, so the
    /// saved password can be entered.
    private static let excluded: Set<String> = Set(TerminalApp.allCases.map(\.bundleIdentifier))
        .union([Bundle.main.bundleIdentifier ?? ""])

    private static let probeURL = URL(string: "sftp://example.com")!

    static var installed: [FileTransferApp] {
        NSWorkspace.shared.urlsForApplications(toOpen: probeURL)
            .compactMap(FileTransferApp.init(url:))
            .filter { !excluded.contains($0.bundleIdentifier) }
            .reduce(into: []) { apps, app in
                // The same app can be installed twice (e.g. App Store and direct download).
                if !apps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) { apps.append(app) }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The app to use for `client`, or `nil` to run `sftp` in the terminal.
    static func resolve(_ client: FileTransferClient) -> FileTransferApp? {
        let apps = installed
        switch client {
        case .terminal:
            return nil
        case .app(let bundleIdentifier):
            // A removed app falls back to the automatic choice.
            return apps.first { $0.bundleIdentifier == bundleIdentifier } ?? resolve(.automatic)
        case .automatic:
            let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: probeURL)
            return apps.first { $0.url == defaultApp } ?? apps.first
        }
    }

    init?(url: URL) {
        guard let bundle = Bundle(url: url), let bundleIdentifier = bundle.bundleIdentifier else { return nil }
        self.bundleIdentifier = bundleIdentifier
        self.url = url
        self.name = FileManager.default.displayName(atPath: url.path).replacing(/\.app$/, with: "")
    }
}

nonisolated enum SFTPLink {
    /// `sftp://user@host:port/`. The password is never part of the link: apps and the system
    /// may log or remember links.
    static func url(for target: ConnectionTarget) -> URL? {
        var components = URLComponents()
        components.scheme = "sftp"
        components.user = target.username.isEmpty ? nil : target.username
        if target.host.contains(":") {
            let address = target.host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            components.percentEncodedHost = "[\(address)]"
        } else {
            components.host = target.host
        }
        components.port = target.port
        components.path = "/"
        return components.url
    }
}
