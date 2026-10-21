import Foundation

/// How an RDP session is shown.
nonisolated enum RDPDisplay: String, CaseIterable, Identifiable, Sendable {
    /// Fits the smallest Mac screen (13" MacBook Air, 1440x900 points) with room for the menu bar and Dock.
    case window1280x800 = "1280x800"
    case window1600x1000 = "1600x1000"
    case window1920x1200 = "1920x1200"
    case fullScreen

    var id: String { rawValue }

    /// The starting window size in pixels; `nil` for full screen. Resizing the window
    /// changes the remote resolution afterwards.
    var size: (width: Int, height: Int)? {
        switch self {
        case .window1280x800: (1280, 800)
        case .window1600x1000: (1600, 1000)
        case .window1920x1200: (1920, 1200)
        case .fullScreen: nil
        }
    }

    var title: String {
        if let size {
            // Plain digits: a localized number would read "1.280" in Turkish.
            String(localized: "Window, \("\(size.width)×\(size.height)")")
        } else {
            String(localized: "Full Screen")
        }
    }
}

/// Where an RDP session's sound plays.
nonisolated enum RDPAudio: String, CaseIterable, Identifiable, Sendable {
    case mac
    case server
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mac: String(localized: "On this Mac")
        case .server: String(localized: "On the server")
        case .off: String(localized: "Off")
        }
    }
}

/// The RDP settings a session opens with.
nonisolated struct RDPOptions: Equatable, Sendable {
    var display = RDPDisplay.window1280x800
    /// All screens; only used in full screen.
    var multiMonitor = false
    var clipboard = true
    /// A Mac folder shown as a drive on the server; `nil` for none. FreeRDP only.
    var sharedFolder: String?
    var audio = RDPAudio.mac

    var usesAllScreens: Bool { display == .fullScreen && multiMonitor }

    func applying(_ overrides: RDPOverrides) -> RDPOptions {
        var options = self
        if let display = overrides.display { options.display = display }
        if let multiMonitor = overrides.multiMonitor { options.multiMonitor = multiMonitor }
        if let clipboard = overrides.clipboard { options.clipboard = clipboard }
        if let sharedFolder = overrides.sharedFolder { options.sharedFolder = sharedFolder.isEmpty ? nil : sharedFolder }
        if let audio = overrides.audio { options.audio = audio }
        return options
    }
}

/// One connection's own RDP settings. `nil` uses the default from Settings.
nonisolated struct RDPOverrides: Equatable, Sendable {
    var display: RDPDisplay?
    var multiMonitor: Bool?
    var clipboard: Bool?
    /// `""` shares no folder even when Settings has a default one.
    var sharedFolder: String?
    var audio: RDPAudio?

    var isEmpty: Bool { self == RDPOverrides() }
}

/// The defaults from Settings, kept in `UserDefaults`.
nonisolated enum RDPDefaults {
    static let displayKey = "rdpDisplay"
    static let multiMonitorKey = "rdpMultiMonitor"
    static let clipboardKey = "rdpClipboard"
    static let sharedFolderKey = "rdpSharedFolder"
    static let audioKey = "rdpAudio"

    static func load(from defaults: UserDefaults = .standard) -> RDPOptions {
        let standard = RDPOptions()
        let folder = defaults.string(forKey: sharedFolderKey) ?? ""
        return RDPOptions(
            display: defaults.string(forKey: displayKey).flatMap(RDPDisplay.init(rawValue:)) ?? standard.display,
            multiMonitor: defaults.object(forKey: multiMonitorKey) as? Bool ?? standard.multiMonitor,
            clipboard: defaults.object(forKey: clipboardKey) as? Bool ?? standard.clipboard,
            sharedFolder: folder.isEmpty ? nil : folder,
            audio: defaults.string(forKey: audioKey).flatMap(RDPAudio.init(rawValue:)) ?? standard.audio
        )
    }
}
