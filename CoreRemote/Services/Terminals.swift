import AppKit
import Foundation

/// The app SSH connections open in.
nonisolated enum TerminalApp: String, CaseIterable, Identifiable, Sendable {
    case terminal
    case iTerm2
    case ghostty
    case warp

    static let storageKey = "terminalApp"
    static let defaultApp = TerminalApp.terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .iTerm2: "iTerm2"
        case .ghostty: "Ghostty"
        case .warp: "Warp"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iTerm2: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        case .warp: "dev.warp.Warp-Stable"
        }
    }

    /// `nil` for Terminal, which comes with macOS.
    var brewCommand: String? {
        switch self {
        case .terminal: nil
        case .iTerm2: "brew install --cask iterm2"
        case .ghostty: "brew install --cask ghostty"
        case .warp: "brew install --cask warp"
        }
    }

    /// The choice saved in Settings, installed or not.
    static var selected: TerminalApp {
        UserDefaults.standard.string(forKey: storageKey).flatMap(TerminalApp.init(rawValue:)) ?? .defaultApp
    }
}

extension TerminalApp {
    var url: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    var isInstalled: Bool { url != nil }

    /// The saved choice, or Terminal when that app has since been removed.
    static var current: TerminalApp {
        let selected = selected
        return selected.isInstalled ? selected : .terminal
    }
}

/// Warp can't open a script file, so a connection opens as a one-off Tab Config that runs it.
nonisolated enum WarpTabConfig {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".warp/tab_configs", directoryHint: .isDirectory)
    }

    /// A Tab Config with one terminal pane that runs `command`.
    static func contents(title: String, command: String) -> String {
        """
        name = \(tomlString(title))

        [[panes]]
        id = "main"
        type = "terminal"
        directory = "~"
        commands = [\(tomlString(command))]

        """
    }

    /// Opens the Tab Config saved as `<stem>.toml` in a new Warp tab.
    static func url(forConfigNamed stem: String) -> URL {
        URL(string: "warp://tab_config/\(stem)")!
    }

    private static func tomlString(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                escaped += String(format: "\\u%04X", scalar.value)
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"\(escaped)\""
    }
}

/// Opening a script file makes iTerm2 ask "OK to run …?" every time. Asking it over AppleScript
/// to run the script in a new window doesn't; macOS asks once whether CoreRemote may control iTerm2.
enum ITerm2Session {
    /// `errAEEventNotPermitted`: the user denied CoreRemote control of iTerm2.
    static let notPermittedError = -1743

    nonisolated static func source(scriptPath: String) -> String {
        let command = "/bin/zsh \(scriptPath.shellQuoted)"
        return """
            tell application id "\(TerminalApp.iTerm2.bundleIdentifier)"
                activate
                create window with default profile command \(appleScriptString(command))
            end tell
            """
    }

    static func open(script url: URL) throws {
        var error: NSDictionary?
        NSAppleScript(source: source(scriptPath: url.path))?.executeAndReturnError(&error)
        guard let error else { return }
        if error[NSAppleScript.errorNumber] as? Int == notPermittedError {
            throw LaunchError.automationDenied(.iTerm2)
        }
        throw LaunchError.scriptFailed(error[NSAppleScript.errorMessage] as? String ?? "")
    }

    nonisolated private static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
