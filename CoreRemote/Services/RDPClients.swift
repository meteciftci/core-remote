import AppKit
import ApplicationServices
import Foundation

nonisolated enum RDPClient: String, CaseIterable, Identifiable, Sendable {
    case windowsApp
    case freeRDP

    static let storageKey = "rdpClient"
    static let defaultClient = RDPClient.freeRDP

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windowsApp: "Windows App"
        case .freeRDP: "FreeRDP"
        }
    }

    var brewCommand: String {
        switch self {
        case .windowsApp: "brew install --cask windows-app"
        case .freeRDP: FreeRDP.brewCommand
        }
    }

    static var current: RDPClient {
        UserDefaults.standard.string(forKey: storageKey).flatMap(RDPClient.init(rawValue:)) ?? .defaultClient
    }
}

extension RDPClient {
    var isInstalled: Bool {
        switch self {
        case .windowsApp: WindowsApp.url != nil
        case .freeRDP: FreeRDP.executableURL != nil
        }
    }
}

// MARK: - Windows App

enum WindowsApp {
    static let bundleIdentifier = "com.microsoft.rdc.macos"
    static let appStoreURL = URL(string: "macappstore://apps.apple.com/app/id1295203466")!
    static let brewCommand = RDPClient.windowsApp.brewCommand
    static let minimizeStorageKey = "minimizeWindowsAppWindow"

    static var url: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    static var minimizesMainWindow: Bool {
        UserDefaults.standard.object(forKey: minimizeStorageKey) as? Bool ?? true
    }
}

/// Minimizes Windows App's own window (its connection list) once a session window is open.
/// Uses the Accessibility API, so it needs the user's permission in System Settings.
enum WindowsAppWindowMinimizer {
    private static let mainWindowTitle = "Windows App"
    private static let requestedKey = "didRequestAccessibility"

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt once; after that the user can use Settings.
    static func requestAccessIfNeeded() {
        guard !isTrusted, !UserDefaults.standard.bool(forKey: requestedKey) else { return }
        UserDefaults.standard.set(true, forKey: requestedKey)
        requestAccess()
    }

    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Waits up to two minutes (the user may still be typing the password) for a window
    /// whose title contains one of `sessionHints`, then minimizes the main window.
    /// Waiting matters: the "Connect to…?" prompt can be attached to the main window.
    static func minimizeMainWindow(sessionHints: [String]) async {
        guard isTrusted else { return }
        let hints = sessionHints.map { $0.lowercased() }.filter { !$0.isEmpty }

        for _ in 0..<240 {
            try? await Task.sleep(for: .milliseconds(500))
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: WindowsApp.bundleIdentifier).first else {
                continue
            }
            let windows = windows(of: app.processIdentifier)
            let titles = windows.map { title(of: $0)?.lowercased() ?? "" }
            guard titles.contains(where: { title in hints.contains { title.contains($0) } }) else { continue }

            for (window, title) in zip(windows, titles) where title == mainWindowTitle.lowercased() {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
            return
        }
    }

    private static func windows(of pid: pid_t) -> [AXUIElement] {
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func title(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

// MARK: - FreeRDP

nonisolated enum FreeRDP {
    static let brewCommand = "brew install freerdp"
    static let executableName = "sdl-freerdp"
    static let searchDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    static var executableURL: URL? {
        searchDirectories
            .map { URL(filePath: $0).appending(path: executableName) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Command-line arguments, one per line when passed through `/args-from:stdin`,
    /// so the password never appears in the process list.
    static func arguments(for target: ConnectionTarget, password: String?) -> [String] {
        let host = target.host.contains(":") && !target.host.hasPrefix("[") ? "[\(target.host)]" : target.host
        var arguments = [
            "/v:\(host):\(target.port)",
            "/u:\(target.username)",
            "/t:\(target.name)",
        ]
        let options = target.rdp
        if let size = options.display.size {
            arguments.append("/size:\(size.width)x\(size.height)")
        } else {
            arguments.append("/f")
        }
        if options.usesAllScreens {
            arguments.append("/multimon")
        }
        arguments += [
            // FreeRDP allows one or the other.
            options.resize == .scale ? "+smart-sizing" : "+dynamic-resolution",
            options.clipboard ? "+clipboard" : "-clipboard",
            // tofu: trust a new certificate on first use, like ssh's accept-new.
            "/cert:\(target.ignoreCertificateErrors ? "ignore" : "tofu")",
        ]
        if let drive = drive(for: options.sharedFolder) {
            arguments.append(drive)
        }
        switch options.audio {
        case .mac: arguments += ["/sound", "/audio-mode:0"]
        case .server: arguments.append("/audio-mode:1")
        case .off: arguments.append("/audio-mode:2")
        }
        if let password, !password.isEmpty {
            arguments.append("/p:\(password)")
        }
        return arguments
    }

    static var failureLogURL: URL {
        URL.libraryDirectory.appending(path: "Logs/CoreRemote/freerdp-last-error.log")
    }

    /// Copies the log of a session that ended with an error, replacing the previous one.
    static func keepFailureLog(_ url: URL) {
        let destination = failureLogURL
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: url, to: destination)
    }

    /// `/drive:<name>,<path>` for a shared folder. FreeRDP splits the value at commas, so a path
    /// with a comma can't be shared.
    static func drive(for folder: String?) -> String? {
        guard let folder, !folder.isEmpty, !folder.contains(",") else { return nil }
        let path = (folder as NSString).expandingTildeInPath
        let name = URL(filePath: path).lastPathComponent
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return "/drive:\(name.isEmpty ? "Mac" : name),\(path)"
    }
}

/// FreeRDP's SDL client makes right Shift its shortcut key by default: right Shift+M minimizes the
/// window and right Shift+D disconnects, so typing a capital letter with that Shift does that
/// instead. Its config file moves the shortcuts to left Control+Option+Shift; FreeRDP only acts
/// when every listed key is down.
nonisolated enum FreeRDPHotkeys {
    static let modifierKey = "SDL_KeyModMask"
    static let modifiers = ["KMOD_LCTRL", "KMOD_LALT", "KMOD_LSHIFT"]

    static func configURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let base = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(filePath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config")
        return base.appending(path: "freerdp/sdl-freerdp.json")
    }

    /// Sets the modifiers unless the file already picks its own. Other settings in the file are
    /// kept, and a file that isn't a JSON object is left alone.
    static func ensureConfigured(at url: URL = configURL()) throws {
        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  existing[modifierKey] == nil else { return }
            settings = existing
        }
        settings[modifierKey] = modifiers
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}

/// Why a FreeRDP session failed, read from its log.
nonisolated enum FreeRDPFailure: Equatable, Sendable {
    case accountLocked
    case wrongCredentials
    case passwordExpired
    case accountDisabled
    case notAllowed
    case hostNotFound
    case unreachable
    case securityNegotiation
    case certificateChanged
    case other(String)

    /// The last connection error in `log`, or `nil` when there is none or the user cancelled.
    static func parse(log: String) -> FreeRDPFailure? {
        if log.contains("Certificate has changed") || log.contains(") has changed!!!") {
            return .certificateChanged
        }
        guard let code = log.matches(of: /ERRCONNECT_[A-Z_]+/).last.map({ String($0.output) }) else { return nil }
        switch code {
        case "ERRCONNECT_CONNECT_CANCELLED": return nil
        case "ERRCONNECT_ACCOUNT_LOCKED_OUT": return .accountLocked
        case "ERRCONNECT_LOGON_FAILURE", "ERRCONNECT_WRONG_PASSWORD", "ERRCONNECT_AUTHENTICATION_FAILED",
             "ERRCONNECT_NO_OR_MISSING_CREDENTIALS":
            return .wrongCredentials
        case "ERRCONNECT_PASSWORD_EXPIRED", "ERRCONNECT_PASSWORD_CERTAINLY_EXPIRED", "ERRCONNECT_PASSWORD_MUST_CHANGE":
            return .passwordExpired
        case "ERRCONNECT_ACCOUNT_DISABLED", "ERRCONNECT_ACCOUNT_EXPIRED": return .accountDisabled
        case "ERRCONNECT_ACCOUNT_RESTRICTION", "ERRCONNECT_LOGON_TYPE_NOT_GRANTED", "ERRCONNECT_INSUFFICIENT_PRIVILEGES",
             "ERRCONNECT_ACCESS_DENIED":
            return .notAllowed
        case "ERRCONNECT_DNS_NAME_NOT_FOUND", "ERRCONNECT_DNS_ERROR": return .hostNotFound
        case "ERRCONNECT_CONNECT_FAILED", "ERRCONNECT_CONNECT_TRANSPORT_FAILED", "ERRCONNECT_ACTIVATION_TIMEOUT":
            return .unreachable
        case "ERRCONNECT_TLS_CONNECT_FAILED", "ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED", "ERRCONNECT_HYBRID_REQUIRED_BY_SERVER":
            return .securityNegotiation
        default: return .other(code)
        }
    }

    var message: String {
        switch self {
        case .accountLocked:
            String(localized: "The account is locked, usually after too many wrong passwords. Wait for it to unlock or ask an administrator, and check that the saved password is current.")
        case .wrongCredentials:
            String(localized: "The user name or password is wrong. Check them in the connection or its credential profile.")
        case .passwordExpired:
            String(localized: "The password has expired. Change it on the server, then save the new one in CoreRemote.")
        case .accountDisabled:
            String(localized: "The account is disabled or has expired.")
        case .notAllowed:
            String(localized: "This account isn't allowed to sign in over Remote Desktop.")
        case .hostNotFound:
            String(localized: "The server name couldn't be found. Check the host and your network or VPN.")
        case .unreachable:
            String(localized: "The server couldn't be reached. Check the host, port and your network or VPN.")
        case .securityNegotiation:
            String(localized: "The server and FreeRDP couldn't agree on a secure connection.")
        case .certificateChanged:
            String(localized: "The server's certificate has changed since the last connection. If that's expected, delete its entry in ~/.config/freerdp/server and connect again.")
        case .other(let code):
            String(localized: "FreeRDP stopped with \(code). The full log is in ~/Library/Logs/CoreRemote/freerdp-last-error.log.")
        }
    }
}
