import Foundation
import SwiftData
import Testing
@testable import CoreRemote

@MainActor
struct TagsTests {
    @Test func normalizeSplitsTrimsAndDedupes() {
        #expect(Tags.normalize(" prod, Linux ,,prod\nPROD, dc ") == ["prod", "Linux", "dc"])
        #expect(Tags.normalize("") == [])
    }

    @Test func countsAreCaseInsensitiveAndSorted() {
        let a = Connection(name: "A", host: "a", type: .ssh, username: "u", tags: ["prod", "linux"])
        let b = Connection(name: "B", host: "b", type: .ssh, username: "u", tags: ["Prod"])
        let counts = Tags.counts(in: [a, b])
        #expect(counts.map(\.tag) == ["linux", "prod"])
        #expect(counts.map(\.count) == [1, 2])
    }

    @Test func sidebarTagFilterIgnoresCase() {
        let a = Connection(name: "A", host: "a", type: .ssh, username: "u", tags: ["Prod"])
        let b = Connection(name: "B", host: "b", type: .ssh, username: "u")
        #expect(SidebarItem.tag("prod").filter([a, b]).map(\.name) == ["A"])
    }

    @Test func draftRoundTripsNotesAndTags() {
        let connection = Connection(name: "A", host: "a", type: .ssh, username: "u")
        var draft = ConnectionDraft(connection: connection, password: nil)
        draft.tagsText = "web, , Web, linux"
        draft.notes = "  hello  \n"
        draft.apply(to: connection, group: nil)
        #expect(connection.tags == ["web", "linux"])
        #expect(connection.notes == "hello")
        #expect(ConnectionDraft(connection: connection, password: nil).tagsText == "web, linux")
    }

    @Test func quickConnectFindsTagsAndNotes() {
        let a = Connection(name: "A", host: "a", type: .ssh, username: "u", notes: "replica of primary", tags: ["postgres"])
        let b = Connection(name: "B", host: "b", type: .ssh, username: "u")
        #expect(QuickConnectSearch.results(for: "postgres", in: [a, b]).map(\.name) == ["A"])
        #expect(QuickConnectSearch.results(for: "replica", in: [a, b]).map(\.name) == ["A"])
    }

    @Test func backupKeepsNotesAndTags() throws {
        let container = try ModelContainer(
            for: Connection.self, ConnectionGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let connection = Connection(name: "A", host: "a", type: .ssh, username: "u", notes: "n", tags: ["x", "y"])
        let payload = BackupStore.payload(connections: [connection], groups: [], includePasswords: false, passwords: InMemoryPasswordStore())
        let decoded = try Backup.decode(try Backup.encode(payload, passphrase: nil), passphrase: nil)

        let context = ModelContext(container)
        _ = try BackupStore.importPayload(decoded, into: context, passwords: InMemoryPasswordStore())
        let imported = try #require(try context.fetch(FetchDescriptor<Connection>()).first)
        #expect(imported.notes == "n")
        #expect(imported.tags == ["x", "y"])
    }

    @Test func olderBackupsWithoutTagsStillImport() throws {
        let json = #"{"format":"coreremote","version":1,"exportedAt":"2026-01-01T00:00:00Z","payload":{"groups":[],"connections":[{"id":"8C1D9F0E-6B57-4A55-9C2B-2B1E7C3F4A11","name":"Old","host":"h","type":"ssh","port":22,"username":"u","isFavorite":false}]}}"#
        let payload = try Backup.decode(Data(json.utf8), passphrase: nil)
        #expect(payload.connections.first?.tags == nil)
        #expect(payload.connections.first?.notes == nil)
    }
}
