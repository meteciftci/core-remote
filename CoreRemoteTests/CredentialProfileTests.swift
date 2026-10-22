import Foundation
import SwiftData
import Testing
@testable import CoreRemote

@MainActor
struct CredentialProfileTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try AppSchema.container(inMemory: true))
    }

    @Test func connectionUsesProfileCredentials() throws {
        let context = try makeContext()
        let profile = CredentialProfile(name: "Domain", username: "EXAMPLE\\admin", keyFilePath: "/keys/id")
        let ssh = Connection(name: "Web", host: "web", type: .ssh, username: "old", keyFilePath: "/keys/own")
        let rdp = Connection(name: "DC", host: "dc", type: .rdp, username: "old")
        [ssh, rdp].forEach(context.insert)
        context.insert(profile)
        ssh.credentialProfile = profile
        rdp.credentialProfile = profile

        #expect(ssh.target.username == "EXAMPLE\\admin")
        #expect(ssh.target.keyFilePath == "/keys/id")
        #expect(ssh.target.keychainID == profile.id)
        #expect(rdp.target.keyFilePath == nil)
        #expect(rdp.summary == "EXAMPLE\\admin@dc:3389")

        rdp.credentialProfile = nil
        #expect(rdp.target.username == "old")
        #expect(rdp.target.keychainID == rdp.id)
    }

    @Test func draftNeedsNoUsernameWithProfile() {
        var draft = ConnectionDraft()
        draft.name = "DC"
        draft.host = "dc"
        #expect(!draft.isValid)
        draft.credentialProfileID = UUID()
        #expect(draft.isValid)
        draft.password = "own"
        #expect(draft.ownPassword == nil)
    }

    @Test func deletingKeepsUsernameAndKey() throws {
        let context = try makeContext()
        let passwords = InMemoryPasswordStore()
        let profile = CredentialProfile(name: "Domain", username: "admin", keyFilePath: "/keys/id")
        let connection = Connection(name: "Web", host: "web", type: .ssh, username: "")
        context.insert(profile)
        context.insert(connection)
        connection.credentialProfile = profile
        try passwords.setPassword("secret", for: profile.id)

        try CredentialProfile.delete(profile, in: context, passwords: passwords)

        #expect(connection.credentialProfile == nil)
        #expect(connection.username == "admin")
        #expect(connection.keyFilePath == "/keys/id")
        #expect(passwords.password(for: profile.id) == nil)
        #expect(try context.fetch(FetchDescriptor<CredentialProfile>()).isEmpty)
    }

    @Test func backupCarriesProfilesWithoutPasswords() throws {
        let source = try makeContext()
        let passwords = InMemoryPasswordStore()
        let profile = CredentialProfile(name: "Domain", username: "admin")
        let connection = Connection(name: "DC", host: "dc", type: .rdp, username: "")
        source.insert(profile)
        source.insert(connection)
        connection.credentialProfile = profile
        try passwords.setPassword("secret", for: profile.id)

        let payload = BackupStore.payload(connections: [connection], groups: [], includePasswords: true, passwords: passwords)
        #expect(payload.profiles == [BackupPayload.Profile(id: profile.id, name: "Domain", username: "admin")])
        let encoded = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        #expect(!encoded.contains("secret"))

        let target = try makeContext()
        _ = try BackupStore.importPayload(payload, into: target, passwords: InMemoryPasswordStore())
        let imported = try #require(try target.fetch(FetchDescriptor<Connection>()).first)
        #expect(imported.credentialProfile?.id == profile.id)
        #expect(imported.effectiveUsername == "admin")
    }

    @Test func olderBackupsWithoutProfilesDecode() throws {
        let json = #"{"groups":[],"connections":[]}"#
        let payload = try JSONDecoder().decode(BackupPayload.self, from: Data(json.utf8))
        #expect(payload.profiles == nil)
    }
}
