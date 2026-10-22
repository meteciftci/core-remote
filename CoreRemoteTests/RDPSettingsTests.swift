import Foundation
import SwiftData
import Testing
@testable import CoreRemote

private func rdpTarget(_ options: RDPOptions = RDPOptions()) -> ConnectionTarget {
    ConnectionTarget(id: UUID(), name: "Win", host: "win.local", type: .rdp, port: 3389, username: "admin", rdp: options)
}

struct RDPOptionsTests {
    @Test func overridesReplaceOnlyWhatTheySet() {
        let defaults = RDPOptions(display: .window1600x1000, clipboard: true, sharedFolder: "/Users/me/Share", audio: .server)
        let options = defaults.applying(RDPOverrides(display: .fullScreen, multiMonitor: true, sharedFolder: ""))
        #expect(options.display == .fullScreen)
        #expect(options.usesAllScreens)
        #expect(options.clipboard)
        #expect(options.sharedFolder == nil)
        #expect(options.audio == .server)
        #expect(defaults.applying(RDPOverrides()) == defaults)
    }

    @Test func allScreensNeedsFullScreen() {
        #expect(!RDPOptions(display: .window1920x1200, multiMonitor: true).usesAllScreens)
    }

    @Test func defaultsComeFromUserDefaults() throws {
        let suite = "RDPDefaultsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(RDPDefaults.load(from: defaults) == RDPOptions())

        defaults.set("fullScreen", forKey: RDPDefaults.displayKey)
        defaults.set(false, forKey: RDPDefaults.clipboardKey)
        defaults.set("/tmp/x", forKey: RDPDefaults.sharedFolderKey)
        defaults.set("off", forKey: RDPDefaults.audioKey)
        #expect(RDPDefaults.load(from: defaults) == RDPOptions(display: .fullScreen, clipboard: false, sharedFolder: "/tmp/x", audio: .off))
    }
}

struct FreeRDPOptionsTests {
    @Test func defaultsMatchTheEarlierCommand() {
        let args = FreeRDP.arguments(for: rdpTarget(), password: nil)
        #expect(args.contains("/size:1280x800"))
        #expect(args.contains("+dynamic-resolution"))
        #expect(args.contains("+clipboard"))
        #expect(args.contains("/sound"))
        #expect(!args.contains("/f"))
        #expect(!args.contains { $0.hasPrefix("/drive:") })
    }

    @Test func fullScreenOnAllScreens() {
        let args = FreeRDP.arguments(for: rdpTarget(RDPOptions(display: .fullScreen, multiMonitor: true)), password: nil)
        #expect(args.contains("/f"))
        #expect(args.contains("/multimon"))
        #expect(!args.contains { $0.hasPrefix("/size:") })
    }

    @Test func clipboardSoundAndFolder() {
        let options = RDPOptions(clipboard: false, sharedFolder: "/Users/me/İş Dosyaları", audio: .off)
        let args = FreeRDP.arguments(for: rdpTarget(options), password: nil)
        #expect(args.contains("-clipboard"))
        #expect(args.contains("/audio-mode:2"))
        #expect(!args.contains("/sound"))
        #expect(args.contains("/drive:İşDosyaları,/Users/me/İş Dosyaları"))
    }

    @Test func skipsFoldersFreeRDPCannotParse() {
        #expect(FreeRDP.drive(for: "/Users/me/a,b") == nil)
        #expect(FreeRDP.drive(for: "") == nil)
        #expect(FreeRDP.drive(for: "/") == "/drive:Mac,/")
    }
}

struct RDPFileOptionsTests {
    @Test func windowSizeAndDevices() {
        let contents = RDPFile.contents(for: rdpTarget(RDPOptions(display: .window1600x1000, clipboard: false, audio: .server)))
        #expect(contents.contains("screen mode id:i:1\r\n"))
        #expect(contents.contains("use multimon:i:0\r\n"))
        #expect(contents.contains("desktopwidth:i:1600\r\n"))
        #expect(contents.contains("desktopheight:i:1000\r\n"))
        #expect(contents.contains("redirectclipboard:i:0\r\n"))
        #expect(contents.contains("audiomode:i:1\r\n"))
    }

    @Test func fullScreenOnAllScreens() {
        let contents = RDPFile.contents(for: rdpTarget(RDPOptions(display: .fullScreen, multiMonitor: true)))
        #expect(contents.contains("screen mode id:i:2\r\n"))
        #expect(contents.contains("use multimon:i:1\r\n"))
        #expect(!contents.contains("desktopwidth"))
    }
}

@MainActor
struct RDPOverridesStorageTests {
    @Test func connectionKeepsOverridesAndDraftClearsThemForSSH() {
        let connection = Connection(name: "Win", host: "win", type: .rdp, username: "admin")
        let overrides = RDPOverrides(display: .fullScreen, clipboard: false, sharedFolder: "", audio: .off)
        connection.rdpOverrides = overrides
        #expect(connection.rdpOverrides == overrides)

        var draft = ConnectionDraft(connection: connection, password: nil)
        #expect(draft.rdp == overrides)
        draft.setType(.ssh)
        draft.apply(to: connection, group: nil)
        #expect(connection.rdpOverrides.isEmpty)
    }

    @Test func backupRoundTripsOverrides() throws {
        let container = try AppSchema.container(inMemory: true)
        let connection = Connection(name: "Win", host: "win", type: .rdp, username: "admin")
        let overrides = RDPOverrides(display: .window1920x1200, resize: .scale, multiMonitor: false, sharedFolder: "/tmp/share", audio: .server)
        connection.rdpOverrides = overrides
        let payload = BackupStore.payload(connections: [connection], groups: [], includePasswords: false, passwords: InMemoryPasswordStore())

        let context = ModelContext(container)
        _ = try BackupStore.importPayload(payload, into: context, passwords: InMemoryPasswordStore())
        let imported = try #require(try context.fetch(FetchDescriptor<Connection>()).first)
        #expect(imported.rdpOverrides == overrides)
    }
}

struct RDPResizeTests {
    @Test func scaleUsesSmartSizingInsteadOfDynamicResolution() {
        let args = FreeRDP.arguments(for: rdpTarget(RDPOptions(resize: .scale)), password: nil)
        #expect(args.contains("+smart-sizing"))
        #expect(!args.contains("+dynamic-resolution"))

        let contents = RDPFile.contents(for: rdpTarget(RDPOptions(resize: .scale)))
        #expect(contents.contains("smart sizing:i:1\r\n"))
        #expect(contents.contains("dynamic resolution:i:0\r\n"))
    }

    @Test func overrideWins() {
        #expect(RDPOptions().applying(RDPOverrides(resize: .scale)).resize == .scale)
    }
}

struct FreeRDPFailureTests {
    @Test func readsTheLastConnectionError() {
        let log = """
            [WARN][com.freerdp.crypto] - [verify_cb]: Certificate verification failure 'self-signed certificate (18)'
            [ERROR][com.freerdp.core] - [nla_recv_pdu]: ERRCONNECT_ACCOUNT_LOCKED_OUT [0x00020018]
            [ERROR][com.freerdp.client.SDL] - [handleShow]: ERRCONNECT_ACCOUNT_LOCKED_OUT [0x00020018]
            """
        #expect(FreeRDPFailure.parse(log: log) == .accountLocked)
        #expect(FreeRDPFailure.parse(log: "x ERRCONNECT_DNS_NAME_NOT_FOUND y") == .hostNotFound)
        #expect(FreeRDPFailure.parse(log: "ERRCONNECT_CONNECT_FAILED [0x00020006]") == .unreachable)
        #expect(FreeRDPFailure.parse(log: "ERRCONNECT_LOGON_FAILURE") == .wrongCredentials)
        #expect(FreeRDPFailure.parse(log: "ERRCONNECT_TARGET_BOOTING") == .other("ERRCONNECT_TARGET_BOOTING"))
    }

    @Test func ignoresCancelledAndCleanLogs() {
        #expect(FreeRDPFailure.parse(log: "ERRCONNECT_CONNECT_CANCELLED") == nil)
        #expect(FreeRDPFailure.parse(log: "[WARN] nothing to see") == nil)
    }

    @Test func detectsChangedCertificates() {
        #expect(FreeRDPFailure.parse(log: "!!!Certificate for dc:3389 (RDP-Server) has changed!!!") == .certificateChanged)
    }
}

struct FreeRDPHotkeysTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "FreeRDPHotkeysTests-\(UUID().uuidString)")
    private var config: URL { folder.appending(path: "freerdp/sdl-freerdp.json") }

    private func read() throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
    }

    @Test func createsTheConfigWithLeftModifiers() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FreeRDPHotkeys.ensureConfigured(at: config)
        #expect(try read()["SDL_KeyModMask"] as? [String] == ["KMOD_LCTRL", "KMOD_LALT", "KMOD_LSHIFT"])
    }

    @Test func keepsOtherSettingsAndTheUsersOwnModifiers() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"SDL_Fullscreen": "SDL_SCANCODE_F"}"#.utf8).write(to: config)
        try FreeRDPHotkeys.ensureConfigured(at: config)
        #expect(try read()["SDL_Fullscreen"] as? String == "SDL_SCANCODE_F")
        #expect(try read()["SDL_KeyModMask"] as? [String] == FreeRDPHotkeys.modifiers)

        try Data(#"{"SDL_KeyModMask": ["KMOD_RGUI"]}"#.utf8).write(to: config)
        try FreeRDPHotkeys.ensureConfigured(at: config)
        #expect(try read()["SDL_KeyModMask"] as? [String] == ["KMOD_RGUI"])
    }

    @Test func leavesFilesItCannotReadAlone() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: config)
        try FreeRDPHotkeys.ensureConfigured(at: config)
        #expect(try String(contentsOf: config, encoding: .utf8) == "not json")
    }

    @Test func followsXDGConfigHome() {
        #expect(FreeRDPHotkeys.configURL(environment: ["XDG_CONFIG_HOME": "/tmp/xdg"]).path == "/tmp/xdg/freerdp/sdl-freerdp.json")
        #expect(FreeRDPHotkeys.configURL(environment: [:]).path.hasSuffix("/.config/freerdp/sdl-freerdp.json"))
    }
}
