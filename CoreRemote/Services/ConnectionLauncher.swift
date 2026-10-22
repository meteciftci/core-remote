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
    private let pasteboard: NSPasteboard
    private var noticeTask: Task<Void, Never>?

    static let clipboardClearDelay: Duration = .seconds(30)
    /// Longer than `clipboardClearDelay`: sudo usually asks a while after the login.
    static let passwordClearDelay: Duration = .seconds(90)
    /// Settings › SSH: copy the password once an SSH connection opens, for sudo.
    static let copiesPasswordAfterSSHKey = "copyPasswordAfterSSH"

    init(passwords: PasswordStore = KeychainPasswordStore.shared, pasteboard: NSPasteboard = .general) {
        self.passwords = passwords
        self.pasteboard = pasteboard
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
        case .ssh:
            try await runInTerminal(connection.target, program: .ssh)
            if UserDefaults.standard.bool(forKey: Self.copiesPasswordAfterSSHKey) {
                copyPassword(for: connection.target, reportsMissing: false)
            }
        case .rdp: try await connectRDP(connection.target)
        }
    }

    func copySSHCommand(for connection: Connection) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(SSHCommand.commandLine(for: connection.target), forType: .string)
        show(String(localized: "SSH command copied"))
    }

    /// Copies the saved password, such as for sudo after logging in, and clears it 90 seconds later.
    func copyPassword(for connection: Connection) {
        copyPassword(for: connection.target, reportsMissing: true)
    }

    private func copyPassword(for target: ConnectionTarget, reportsMissing: Bool) {
        guard let password = passwords.password(for: target.keychainID) else {
            if reportsMissing { show(String(localized: "No password is saved for this connection")) }
            return
        }
        Clipboard.copyConcealed(password, clearAfter: Self.passwordClearDelay, on: pasteboard)
        show(String(localized: "Password copied — clears in 90 seconds"))
    }

    /// Opens an SSH connection's files in a file transfer app, or `sftp` in the terminal.
    /// Failures are kept in `launchProblem`, like `open(_:)`.
    func openFileTransfer(_ connection: Connection) async {
        do {
            try await transferFiles(connection.target)
        } catch {
            launchProblem = .failed(name: connection.name, message: error.localizedDescription)
        }
    }

    // MARK: - SSH

    private func transferFiles(_ target: ConnectionTarget) async throws {
        guard let app = FileTransferApp.resolve(.selected) else {
            try await runInTerminal(target, program: .sftp)
            return
        }
        guard let link = SFTPLink.url(for: target) else {
            throw LaunchError.scriptFailed(String(localized: "The host name can't be used in a link."))
        }
        if let password = passwords.password(for: target.keychainID) {
            Clipboard.copyConcealed(password, clearAfter: Self.clipboardClearDelay, on: pasteboard)
            show(String(localized: "Password copied — clears in 30 seconds"))
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.open([link], withApplicationAt: app.url, configuration: configuration)
    }

    private func runInTerminal(_ target: ConnectionTarget, program: SSHProgram) async throws {
        let terminal = TerminalApp.current
        guard let terminalURL = terminal.url else {
            throw LaunchError.terminalMissing(terminal)
        }

        var askpass: AskpassEnvironment?
        if let password = passwords.password(for: target.keychainID) {
            let helper = try AskpassHelper.install()
            let passwordFile = try LaunchFiles.write(password, named: "\(UUID().uuidString).pass")
            // The helper deletes it on first use; this covers logins that never ask (e.g. key auth).
            LaunchFiles.remove(passwordFile, after: .seconds(60))
            askpass = AskpassEnvironment(helperPath: helper.path, passwordFilePath: passwordFile.path)
        }

        let scriptURL = try LaunchFiles.write(
            SSHCommand.script(
                for: target,
                program: program,
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

        if let password = passwords.password(for: target.keychainID) {
            Clipboard.copyConcealed(password, clearAfter: Self.clipboardClearDelay, on: pasteboard)
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
        // Keeps right Shift for capital letters; without the file it minimizes or disconnects.
        try? FreeRDPHotkeys.ensureConfigured()

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

        // FreeRDP reports connection problems in its own window, so the log is only kept when it
        // fails, as ~/Library/Logs/CoreRemote/freerdp-last-error.log. The password goes through
        // stdin and isn't in it.
        process.terminationHandler = { [weak self] process in
            var failure: FreeRDPFailure?
            if process.terminationStatus != 0 {
                FreeRDP.keepFailureLog(logURL)
                failure = (try? String(contentsOf: logURL, encoding: .utf8)).flatMap(FreeRDPFailure.parse(log:))
            }
            try? FileManager.default.removeItem(at: logURL)
            guard let failure else { return }
            Task { @MainActor in
                guard let self else { return }
                LaunchProblemAlert.run(.failed(name: target.name, message: failure.message), launcher: self)
            }
        }

        try process.run()
        let arguments = FreeRDP.arguments(for: target, password: passwords.password(for: target.keychainID))
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
    static func copyConcealed(_ string: String, clearAfter delay: Duration, on pasteboard: NSPasteboard = .general) {
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
