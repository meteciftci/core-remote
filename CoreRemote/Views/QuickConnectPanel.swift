import AppKit
import KeyboardShortcuts
import SwiftData
import SwiftUI

extension KeyboardShortcuts.Name {
    /// ⌃⌥Space by default; ⌥Space alone is taken by several other apps.
    static let quickConnect = Self("quickConnect", initial: .init(.space, modifiers: [.control, .option]))
}

/// Floating panel that hosts `QuickConnectView`. It takes keyboard focus without activating
/// CoreRemote, like Spotlight, and hides as soon as it loses focus.
@MainActor
final class QuickConnectPanel {
    static let shared = QuickConnectPanel()
    static let size = CGSize(width: 640, height: 420)

    private var panel: FloatingPanel?
    private var container: ModelContainer?
    private var launcher: ConnectionLauncher?

    func configure(container: ModelContainer, launcher: ConnectionLauncher) {
        self.container = container
        self.launcher = launcher
        KeyboardShortcuts.onKeyUp(for: .quickConnect) { [weak self] in
            self?.toggle()
        }
    }

    func toggle() {
        if panel?.isVisible == true {
            close()
        } else {
            show()
        }
    }

    func show() {
        guard let container, let launcher else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        // A fresh view each time, so the search starts empty.
        panel.contentView = NSHostingView(
            rootView: QuickConnectView(onClose: { [weak self] in self?.close() })
                .modelContainer(container)
                .environment(launcher)
        )
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.onResignKey = { [weak self] in self?.close() }
        return panel
    }

    /// Centered horizontally, a little above the middle, on the screen with the mouse.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = CGPoint(
            x: frame.midX - Self.size.width / 2,
            y: frame.minY + frame.height * 0.62 - Self.size.height / 2
        )
        panel.setFrame(CGRect(origin: origin, size: Self.size), display: false)
    }
}

final class FloatingPanel: NSPanel {
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// Shows a launch problem in a standalone alert, for launches that have no window around them.
enum LaunchProblemAlert {
    @MainActor
    static func run(_ problem: LaunchProblem, launcher: ConnectionLauncher) {
        NSApp.activate()
        let alert = NSAlert()
        switch problem {
        case .failed(let name, let message):
            alert.messageText = name.isEmpty ? String(localized: "Couldn't Connect") : String(localized: "Couldn't connect to “\(name)”")
            alert.informativeText = message
            alert.runModal()
        case .missingClient(let client):
            alert.messageText = String(localized: "\(client.title) is required")
            alert.informativeText = switch client {
            case .windowsApp:
                String(localized: "RDP connections open in Microsoft Windows App. Install it from the App Store, or with Homebrew:\n\n\(client.brewCommand)")
            case .freeRDP:
                String(localized: "RDP connections are set to open in FreeRDP. Install it with Homebrew, or choose Windows App in Settings:\n\n\(client.brewCommand)")
            }
            alert.addButton(withTitle: String(localized: "Copy brew Command"))
            if client == .windowsApp {
                alert.addButton(withTitle: String(localized: "Open App Store"))
            }
            alert.addButton(withTitle: String(localized: "Cancel"))
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(client.brewCommand, forType: .string)
            case .alertSecondButtonReturn where client == .windowsApp:
                NSWorkspace.shared.open(WindowsApp.appStoreURL)
            default:
                break
            }
        }
    }
}
