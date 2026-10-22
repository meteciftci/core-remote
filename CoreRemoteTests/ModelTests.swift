import Foundation
import SwiftData
import Testing
@testable import CoreRemote

struct ConnectionDraftTests {
    @Test func defaultPortFollowsType() {
        var draft = ConnectionDraft()
        #expect(draft.port == 22)
        draft.setType(.rdp)
        #expect(draft.port == 3389)
        draft.setType(.ssh)
        #expect(draft.port == 22)
    }

    @Test func customPortIsKept() {
        var draft = ConnectionDraft()
        draft.port = 2222
        draft.setType(.rdp)
        #expect(draft.port == 2222)
    }

    @Test func emptyPortGetsDefault() {
        var draft = ConnectionDraft()
        draft.port = nil
        draft.setType(.rdp)
        #expect(draft.port == 3389)
    }

    @Test func validation() {
        var draft = ConnectionDraft()
        draft.name = "Server"
        draft.host = "10.0.0.1"
        #expect(!draft.isValid, "username is required")
        draft.username = "root"
        #expect(draft.isValid)
        draft.port = 70000
        #expect(!draft.isValid)
        draft.port = 22
        draft.host = "bad host"
        #expect(!draft.isValid)
    }

    @Test func keyFileOnlyForSSH() {
        var draft = ConnectionDraft()
        draft.keyFilePath = "~/.ssh/id"
        #expect(draft.trimmedKeyFilePath == "~/.ssh/id")
        draft.setType(.rdp)
        #expect(draft.trimmedKeyFilePath == nil)
    }
}

struct BackupTests {
    private let payload = BackupPayload(
        groups: ["Home", "Work"],
        connections: [
            .init(id: UUID(), name: "Pi", host: "10.0.0.2", type: .ssh, port: 22, username: "pi",
                  keyFilePath: nil, isFavorite: true, group: "Home", password: "raspberry"),
            .init(id: UUID(), name: "Desktop", host: "win", type: .rdp, port: 3389, username: "admin",
                  keyFilePath: nil, isFavorite: false, group: nil, password: nil),
        ]
    )

    @Test func plainExportDropsPasswords() throws {
        let data = try Backup.encode(payload, passphrase: nil)
        #expect(try !Backup.isEncrypted(data))
        #expect(!String(decoding: data, as: UTF8.self).contains("raspberry"))
        let decoded = try Backup.decode(data, passphrase: nil)
        #expect(decoded.connections.map(\.name) == ["Pi", "Desktop"])
        #expect(!decoded.hasPasswords)
    }

    @Test func encryptedRoundTrip() throws {
        let data = try Backup.encode(payload, passphrase: "correct horse", iterations: 1_000)
        #expect(try Backup.isEncrypted(data))
        #expect(!String(decoding: data, as: UTF8.self).contains("raspberry"))
        #expect(try Backup.decode(data, passphrase: "correct horse") == payload)
    }

    @Test func encryptedNeedsCorrectPassphrase() throws {
        let data = try Backup.encode(payload, passphrase: "correct horse", iterations: 1_000)
        #expect(throws: BackupError.passphraseRequired) { try Backup.decode(data, passphrase: nil) }
        #expect(throws: BackupError.wrongPassphrase) { try Backup.decode(data, passphrase: "wrong") }
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: BackupError.invalidFile) { try Backup.decode(Data("{}".utf8), passphrase: nil) }
        #expect(throws: BackupError.invalidFile) { try Backup.decode(Data("nope".utf8), passphrase: nil) }
    }

    @Test func rejectsNewerVersions() {
        let data = Data(#"{"format":"coreremote","version":99,"exportedAt":"2026-01-01T00:00:00Z"}"#.utf8)
        #expect(throws: BackupError.unsupportedVersion(99)) { try Backup.decode(data, passphrase: nil) }
    }
}

@MainActor
struct ImportTests {
    private func makeContext() throws -> ModelContext {
        let container = try AppSchema.container(inMemory: true)
        return ModelContext(container)
    }

    @Test func importsSkipsDuplicatesAndMatchesGroups() throws {
        let context = try makeContext()
        let existing = Connection(name: "Existing", host: "a", type: .ssh, username: "u")
        context.insert(existing)
        context.insert(ConnectionGroup(name: "Work"))
        try context.save()

        let newID = UUID()
        let payload = BackupPayload(
            groups: ["work", "Lab"],
            connections: [
                .init(id: existing.id, name: "Existing", host: "a", type: .ssh, port: 22, username: "u",
                      keyFilePath: nil, isFavorite: false, group: nil, password: nil),
                .init(id: newID, name: "New", host: "b", type: .rdp, port: 3389, username: "v",
                      keyFilePath: "/ignored", isFavorite: true, group: "WORK", password: "pw"),
            ]
        )
        let passwords = InMemoryPasswordStore()
        let summary = try BackupStore.importPayload(payload, into: context, passwords: passwords)

        #expect(summary == ImportSummary(added: 1, skipped: 1, groupsCreated: 1))
        let groups = try context.fetch(FetchDescriptor<ConnectionGroup>(sortBy: [SortDescriptor(\.name)]))
        #expect(groups.map(\.name) == ["Lab", "Work"])

        let imported = try #require(try context.fetch(FetchDescriptor<Connection>()).first { $0.id == newID })
        #expect(imported.group?.name == "Work")
        #expect(imported.keyFilePath == nil)
        #expect(passwords.password(for: newID) == "pw")
    }

    @Test func exportPayloadIncludesPasswordsOnlyWhenAsked() throws {
        let context = try makeContext()
        let group = ConnectionGroup(name: "Home")
        let connection = Connection(name: "Pi", host: "pi", type: .ssh, username: "pi", group: group)
        context.insert(group)
        context.insert(connection)
        let passwords = InMemoryPasswordStore()
        try passwords.setPassword("secret", for: connection.id)

        let without = BackupStore.payload(connections: [connection], groups: [group], includePasswords: false, passwords: passwords)
        #expect(without.connections.first?.password == nil)
        #expect(without.connections.first?.group == "Home")

        let with = BackupStore.payload(connections: [connection], groups: [group], includePasswords: true, passwords: passwords)
        #expect(with.connections.first?.password == "secret")
    }
}
