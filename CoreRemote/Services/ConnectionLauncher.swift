import AppKit
import Foundation

enum LaunchError: LocalizedError {
    case windowsAppMissing
    case terminalMissing

    var errorDescription: String? {
        switch self {
        case .windowsAppMissing: String(localized: "Windows App is not installed")
        case .terminalMissing: String(localized: "Terminal could not be found")
        }
    }
}

enum WindowsApp {
    static let bundleIdentifier = "com.microsoft.rdc.macos"
    static let appStoreURL = URL(string: "macappstore://apps.apple.com/app/id1295203466")!
    static let brewCommand = "brew install --cask windows-app"

    static var url: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}

/// Opens connections: SSH in Terminal, RDP in Windows App.
@Observable
final class ConnectionLauncher {
    /// Short message shown as a toast, such as "Password copied".
    private(set) var notice: String?

    private let passwords: PasswordStore
    private var noticeTask: Task<Void, Never>?

    static let terminalBundleIdentifier = "com.apple.Terminal"
    static let clipboardClearDelay: Duration = .seconds(30)

    init(passwords: PasswordStore = KeychainPasswordStore.shared) {
        self.passwords = passwords
    }

    func connect(_ connection: Connection) async throws {
        switch connection.type {
        case .ssh: try await connectSSH(connection.target)
        case .rdp: try await connectRDP(connection.target)
        }
    }

    func copySSHCommand(for connection: Connection) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(SSHCommand.commandLine(for: connection.target), forType: .string)
        show(String(localized: "SSH command copied"))
    }

    // MARK: - SSH

    private func connectSSH(_ target: ConnectionTarget) async throws {
        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.terminalBundleIdentifier) else {
            throw LaunchError.terminalMissing
        }

        var askpass: AskpassEnvironment?
        if let password = passwords.password(for: target.id) {
            let helper = try AskpassHelper.install()
            let passwordFile = try LaunchFiles.write(password, named: "\(UUID().uuidString).pass")
            // The helper deletes it on first use; this covers logins that never ask (e.g. key auth).
            LaunchFiles.remove(passwordFile, after: .seconds(60))
            askpass = AskpassEnvironment(helperPath: helper.path, passwordFilePath: passwordFile.path)
        }

        let script = """
            #!/bin/zsh
            rm -f -- "$0"
            clear
            \(SSHCommand.commandLine(for: target, askpass: askpass))

            """
        let scriptURL = try LaunchFiles.write(
            script,
            named: LaunchFiles.fileName(for: target.name, extension: "command"),
            permissions: 0o700
        )

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.open([scriptURL], withApplicationAt: terminalURL, configuration: configuration)
    }

    // MARK: - RDP

    private func connectRDP(_ target: ConnectionTarget) async throws {
        guard let appURL = WindowsApp.url else { throw LaunchError.windowsAppMissing }

        let fileURL = try LaunchFiles.write(
            RDPFile.contents(for: target),
            named: LaunchFiles.fileName(for: target.name, extension: "rdp")
        )
        LaunchFiles.remove(fileURL, after: .seconds(120))

        if let password = passwords.password(for: target.id) {
            Clipboard.copyConcealed(password, clearAfter: Self.clipboardClearDelay)
            show(String(localized: "Password copied — clears in 30 seconds"))
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: configuration)
    }

    // MARK: - Notices

    func show(_ message: String) {
        noticeTask?.cancel()
        notice = message
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }
}

enum Clipboard {
    /// Copies a secret, marked so clipboard managers skip it,
    /// and clears it later unless something else was copied in the meantime.
    static func copyConcealed(_ string: String, clearAfter delay: Duration) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let changeCount = pasteboard.changeCount

        Task {
            try? await Task.sleep(for: delay)
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
            }
        }
    }
}
