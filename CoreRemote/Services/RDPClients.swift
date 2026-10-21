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
            // Ask the server for a new resolution when the window is resized, instead of
            // stretching the picture.
            "+dynamic-resolution",
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
