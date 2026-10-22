import AppKit
import Foundation
import Testing
@testable import CoreRemote

@MainActor
struct PasswordCopyTests {
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasswordCopyTests-\(UUID().uuidString)"))

    @Test func copiesTheSavedPasswordConcealed() throws {
        let passwords = InMemoryPasswordStore()
        let connection = Connection(name: "Web", host: "web", type: .ssh, username: "deploy")
        try passwords.setPassword("s3cret", for: connection.id)
        let launcher = ConnectionLauncher(passwords: passwords, pasteboard: pasteboard)

        launcher.copyPassword(for: connection)

        #expect(pasteboard.string(forType: .string) == "s3cret")
        #expect(pasteboard.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true)
        #expect(launcher.notice == String(localized: "Password copied — clears in 90 seconds"))
        pasteboard.releaseGlobally()
    }

    @Test func usesTheProfilePassword() throws {
        let passwords = InMemoryPasswordStore()
        let profile = CredentialProfile(name: "Domain", username: "admin")
        let connection = Connection(name: "DC", host: "dc", type: .rdp, username: "")
        connection.credentialProfile = profile
        try passwords.setPassword("domain", for: profile.id)
        let launcher = ConnectionLauncher(passwords: passwords, pasteboard: pasteboard)

        launcher.copyPassword(for: connection)

        #expect(pasteboard.string(forType: .string) == "domain")
        pasteboard.releaseGlobally()
    }

    @Test func leavesTheClipboardAloneWithoutAPassword() {
        pasteboard.clearContents()
        pasteboard.setString("mine", forType: .string)
        let launcher = ConnectionLauncher(passwords: InMemoryPasswordStore(), pasteboard: pasteboard)

        launcher.copyPassword(for: Connection(name: "Pi", host: "pi", type: .ssh, username: "pi"))

        #expect(pasteboard.string(forType: .string) == "mine")
        #expect(launcher.notice == String(localized: "No password is saved for this connection"))
        pasteboard.releaseGlobally()
    }

    @Test func copyingAfterSSHIsOffByDefault() {
        #expect(!UserDefaults(suiteName: "PasswordCopyTests-\(UUID().uuidString)")!.bool(forKey: ConnectionLauncher.copiesPasswordAfterSSHKey))
    }
}
