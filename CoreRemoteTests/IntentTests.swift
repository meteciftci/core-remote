import Foundation
import SwiftData
import Testing
@testable import CoreRemote

@MainActor
struct IntentTests {
    private func makeContext() throws -> ModelContext {
        let container = try AppSchema.container(inMemory: true)
        return ModelContext(container)
    }

    @Test func entityShowsNameAndSummary() {
        let connection = Connection(name: "Web", host: "web.example.com", type: .ssh, username: "deploy")
        let entity = ConnectionEntity(connection)
        #expect(entity.id == connection.id)
        #expect(entity.name == "Web")
        #expect(entity.summary == "deploy@web.example.com:22")
        #expect(entity.symbol == ConnectionType.ssh.symbol)
    }

    @Test func lookupByIDKeepsRequestedOrderAndSkipsMissing() throws {
        let context = try makeContext()
        let a = Connection(name: "A", host: "a", type: .ssh, username: "u")
        let b = Connection(name: "B", host: "b", type: .rdp, username: "u")
        context.insert(a)
        context.insert(b)
        try context.save()

        let entities = try ConnectionEntityLookup.entities(for: [b.id, UUID(), a.id], in: context)
        #expect(entities.map(\.name) == ["B", "A"])
    }

    @Test func matchingUsesQuickConnectRanking() throws {
        let context = try makeContext()
        context.insert(Connection(name: "Old db server", host: "x", type: .ssh, username: "u"))
        context.insert(Connection(name: "DB Primary", host: "y", type: .ssh, username: "u"))
        context.insert(Connection(name: "Web", host: "z", type: .ssh, username: "u"))
        try context.save()

        #expect(try ConnectionEntityLookup.entities(matching: "db", in: context).map(\.name) == ["DB Primary", "Old db server"])
        #expect(try ConnectionEntityLookup.entities(matching: "", in: context).count == 3)
    }
}

struct ConnectURLTests {
    @Test func roundTripsConnectionID() {
        let id = UUID()
        let url = ConnectURL.url(for: id)
        #expect(url.absoluteString == "coreremote://connect/\(id.uuidString)")
        #expect(ConnectURL.connectionID(from: url) == id)
    }

    @Test func rejectsOtherURLs() {
        #expect(ConnectURL.connectionID(from: URL(string: "coreremote://open/\(UUID().uuidString)")!) == nil)
        #expect(ConnectURL.connectionID(from: URL(string: "https://connect/\(UUID().uuidString)")!) == nil)
        #expect(ConnectURL.connectionID(from: URL(string: "coreremote://connect/not-a-uuid")!) == nil)
    }
}
