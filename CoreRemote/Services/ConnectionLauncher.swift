import AppKit
import Foundation

enum LaunchError: LocalizedError {
    case clientMissing(RDPClient)
    case terminalMissing(TerminalApp)
    case automationDenied(TerminalApp)
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .clientMissing(let client): String(localized: "\(client.title) is not installed")
        case .terminalMissing(let app): String(localized: "\(app.title) could not be found")
        case .automationDenied(let app): String(localized: "Allow CoreRemote to control \(app.title) in System Settings > Privacy & Security > Automation.")
        case .scriptFailed(let message): message
        }
    }
}

enum LaunchProblem: Equatable {
    case missingClient(RDPClient)
    case failed(name: String, message: String)
}

/// Opens connections: SSH in the chosen terminal app, RDP in Windows App or FreeRDP.
@Observable
final class ConnectionLauncher {
    /// Short message shown as a toast, such as "Password copied".
    private(set) var notice: String?

    private let passwords: PasswordStore
    private var noticeTask: Task<Void, Never>?

    static let clipboardClearDelay: Duration = .seconds(30)

    init(passwords: PasswordStore = KeychainPasswordStore.shared) {
        self.passwords = passwords
    }

    /// A problem from the last launch, waiting for the main window to show it.
    var launchProblem: LaunchProblem?

    /// Opens a connection from anywhere in the app (main window, menu bar) and remembers when.
    /// Failures are kept in `launchProblem` rather than thrown, since the caller may have no UI.
    func open(_ connection: Connection) async {
        do {
            try await connect(connection)
            connection.lastConnectedAt = .now
            try? connection.modelContext?.save()
        } catch LaunchError.clientMissing(let client) {
            launchProblem = .missingClient(client)
        } catch {
            launchProblem = .failed(name: connection.name, message: error.localizedDescription)
        }
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
        let terminal = TerminalApp.current
        guard let terminalURL = terminal.url else {
            throw LaunchError.terminalMissing(terminal)
        }

        var askpass: AskpassEnvironment?
        if let password = passwords.password(for: target.id) {
            let helper = try AskpassHelper.install()
            let passwordFile = try LaunchFiles.write(password, named: "\(UUID().uuidString).pass")
            // The helper deletes it on first use; this covers logins that never ask (e.g. key auth).
            LaunchFiles.remove(passwordFile, after: .seconds(60))
            askpass = AskpassEnvironment(helperPath: helper.path, passwordFilePath: passwordFile.path)
        }

        let scriptURL = try LaunchFiles.write(
            SSHCommand.script(
                for: target,
                askpass: askpass,
                failureMessage: String(localized: "Connection closed. Exit code:"),
                closePrompt: String(localized: "Press any key to close this window.")
            ),
            named: LaunchFiles.fileName(for: target.name, extension: "command"),
            permissions: 0o700
        )

        switch terminal {
        case .iTerm2:
            try ITerm2Session.open(script: scriptURL)
        case .terminal:
            // Terminal runs a `.command` file it's asked to open.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            try await NSWorkspace.shared.open([scriptURL], withApplicationAt: terminalURL, configuration: configuration)
        }
    }

    // MARK: - RDP

    private func connectRDP(_ target: ConnectionTarget) async throws {
        switch RDPClient.current {
        case .windowsApp: try await connectWindowsApp(target)
        case .freeRDP: try connectFreeRDP(target)
        }
    }

    private func connectWindowsApp(_ target: ConnectionTarget) async throws {
        guard let appURL = WindowsApp.url else { throw LaunchError.clientMissing(.windowsApp) }

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

        if WindowsApp.minimizesMainWindow {
            WindowsAppWindowMinimizer.requestAccessIfNeeded()
            let hints = [target.host, fileURL.deletingPathExtension().lastPathComponent]
            Task { await WindowsAppWindowMinimizer.minimizeMainWindow(sessionHints: hints) }
        }
    }

    private func connectFreeRDP(_ target: ConnectionTarget) throws {
        guard let executable = FreeRDP.executableURL else { throw LaunchError.clientMissing(.freeRDP) }

        let logURL = try LaunchFiles.write("", named: "\(UUID().uuidString).freerdp.log")
        let log = try FileHandle(forWritingTo: logURL)
        let input = Pipe()

        let process = Process()
        process.executableURL = executable
        process.arguments = ["/args-from:stdin"]
        process.standardInput = input
        process.standardOutput = log
        process.standardError = log
        var environment = ProcessInfo.processInfo.environment
        // SDL otherwise passes through a fullscreen Space when it creates the window,
        // which slides the whole screen away and back.
        environment["SDL_VIDEO_MAC_FULLSCREEN_SPACES"] = "0"
        process.environment = environment

        // FreeRDP reports connection problems in its own window, so the log is only kept while it runs.
        process.terminationHandler = { _ in
            try? FileManager.default.removeItem(at: logURL)
        }

        try process.run()
        let arguments = FreeRDP.arguments(for: target, password: passwords.password(for: target.id))
        input.fileHandleForWriting.write(Data((arguments.joined(separator: "\n") + "\n").utf8))
        try? input.fileHandleForWriting.close()
        try? log.close()
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
