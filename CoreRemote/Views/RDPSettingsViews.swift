import AppKit
import SwiftUI

/// The RDP defaults in Settings.
struct RDPDefaultsSection: View {
    @AppStorage(RDPDefaults.displayKey) private var display = RDPOptions().display
    @AppStorage(RDPDefaults.resizeKey) private var resize = RDPOptions().resize
    @AppStorage(RDPDefaults.multiMonitorKey) private var multiMonitor = RDPOptions().multiMonitor
    @AppStorage(RDPDefaults.clipboardKey) private var clipboard = RDPOptions().clipboard
    @AppStorage(RDPDefaults.sharedFolderKey) private var sharedFolder = ""
    @AppStorage(RDPDefaults.audioKey) private var audio = RDPOptions().audio

    var body: some View {
        Section {
            Picker("Display", selection: $display) {
                ForEach(RDPDisplay.allCases) { Text(verbatim: $0.title).tag($0) }
            }
            Picker("When resized", selection: $resize) {
                ForEach(RDPResize.allCases) { Text(verbatim: $0.title).tag($0) }
            }
            Toggle("Use all screens", isOn: $multiMonitor)
                .disabled(display != .fullScreen)
            Toggle("Share clipboard", isOn: $clipboard)
            LabeledContent("Shared folder") {
                FolderField(path: sharedFolder.isEmpty ? nil : sharedFolder) { sharedFolder = $0 ?? "" }
            }
            Picker("Sound", selection: $audio) {
                ForEach(RDPAudio.allCases) { Text(verbatim: $0.title).tag($0) }
            }
        } header: {
            Text("RDP Sessions")
        } footer: {
            Text("Each RDP connection can change these in its editor. Changing the resolution needs Windows 8.1 or Server 2012 R2 or later; if the window doesn't resize, choose Scale picture. All screens needs full screen. A shared folder appears as a drive on the server and works with FreeRDP only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One RDP connection's settings in the editor; every field can follow the default.
struct RDPOverridesSection: View {
    @Binding var overrides: RDPOverrides

    @AppStorage(RDPDefaults.displayKey) private var defaultDisplayRaw = ""
    @AppStorage(RDPDefaults.resizeKey) private var defaultResizeRaw = ""
    @AppStorage(RDPDefaults.multiMonitorKey) private var defaultMultiMonitor = RDPOptions().multiMonitor
    @AppStorage(RDPDefaults.clipboardKey) private var defaultClipboard = RDPOptions().clipboard
    @AppStorage(RDPDefaults.sharedFolderKey) private var defaultSharedFolder = ""
    @AppStorage(RDPDefaults.audioKey) private var defaultAudioRaw = ""

    private var defaults: RDPOptions { RDPDefaults.load() }
    private var resolved: RDPOptions { defaults.applying(overrides) }

    var body: some View {
        // Reading the stored defaults keeps the "Default (…)" labels current while Settings changes them.
        let _ = (defaultDisplayRaw, defaultResizeRaw, defaultMultiMonitor, defaultClipboard, defaultSharedFolder, defaultAudioRaw)
        Section {
            Picker("Display", selection: $overrides.display) {
                Text("Default (\(defaults.display.title))").tag(RDPDisplay?.none)
                Divider()
                ForEach(RDPDisplay.allCases) { Text(verbatim: $0.title).tag(RDPDisplay?.some($0)) }
            }
            Picker("When resized", selection: $overrides.resize) {
                Text("Default (\(defaults.resize.title))").tag(RDPResize?.none)
                Divider()
                ForEach(RDPResize.allCases) { Text(verbatim: $0.title).tag(RDPResize?.some($0)) }
            }
            Picker("Use all screens", selection: $overrides.multiMonitor) {
                Text("Default (\(onOff(defaults.multiMonitor)))").tag(Bool?.none)
                Divider()
                Text("On").tag(Bool?.some(true))
                Text("Off").tag(Bool?.some(false))
            }
            .disabled(resolved.display != .fullScreen)
            Picker("Share clipboard", selection: $overrides.clipboard) {
                Text("Default (\(onOff(defaults.clipboard)))").tag(Bool?.none)
                Divider()
                Text("On").tag(Bool?.some(true))
                Text("Off").tag(Bool?.some(false))
            }
            LabeledContent("Shared folder") {
                Menu(folderTitle) {
                    Button("Default (\(folderName(defaults.sharedFolder)))") { overrides.sharedFolder = nil }
                    Button("None") { overrides.sharedFolder = "" }
                    Divider()
                    Button("Choose…") {
                        if let path = FolderField.choose() { overrides.sharedFolder = path }
                    }
                }
                .fixedSize()
            }
            Picker("Sound", selection: $overrides.audio) {
                Text("Default (\(defaults.audio.title))").tag(RDPAudio?.none)
                Divider()
                ForEach(RDPAudio.allCases) { Text(verbatim: $0.title).tag(RDPAudio?.some($0)) }
            }
        } header: {
            Text("Session")
        } footer: {
            Text("\"Default\" follows Settings. All screens needs full screen; a shared folder works with FreeRDP only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var folderTitle: String {
        switch overrides.sharedFolder {
        case nil: String(localized: "Default (\(folderName(defaults.sharedFolder)))")
        case let path?: folderName(path.isEmpty ? nil : path)
        }
    }

    private func folderName(_ path: String?) -> String {
        guard let path else { return String(localized: "None") }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private func onOff(_ value: Bool) -> String {
        value ? String(localized: "On") : String(localized: "Off")
    }
}

/// A folder path with Choose… and Clear buttons.
struct FolderField: View {
    var path: String?
    var onChange: (String?) -> Void

    var body: some View {
        HStack {
            Text(path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? String(localized: "None"))
                .foregroundStyle(path == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if path != nil {
                Button("Clear", systemImage: "xmark.circle.fill") { onChange(nil) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            Button("Choose…") {
                if let chosen = Self.choose() { onChange(chosen) }
            }
        }
    }

    static func choose() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Share")
        panel.message = String(localized: "Choose a folder to show as a drive on the server.")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
