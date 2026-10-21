import Foundation
import SwiftData
import Testing
@testable import CoreRemote

@MainActor
struct IntentTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Connection.self, ConnectionGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
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

    @Test func shortcutRunsConnectWithThePickedConnection() throws {
        let connection = Connection(name: "SAS-DB", host: "db.example.com", type: .ssh, username: "sa")
        let workflow = ShortcutExport.workflow(for: ConnectionEntity(connection), bundleID: "com.example.app", teamID: "TEAM123")
        let actions = try #require(workflow["WFWorkflowActions"] as? [[String: Any]])
        #expect(actions.count == 1)
        #expect(actions.first?["WFWorkflowActionIdentifier"] as? String == "com.example.app.ConnectIntent")

        let parameters = try #require(actions.first?["WFWorkflowActionParameters"] as? [String: Any])
        let descriptor = try #require(parameters["AppIntentDescriptor"] as? [String: Any])
        #expect(descriptor["AppIntentIdentifier"] as? String == "ConnectIntent")
        #expect(descriptor["BundleIdentifier"] as? String == "com.example.app")
        #expect(descriptor["TeamIdentifier"] as? String == "TEAM123")

        // Same shape Kestirmeler writes when the connection is picked by hand.
        let target = try #require(parameters["target"] as? [String: Any])
        #expect(target["identifier"] as? String == connection.id.uuidString)
        #expect((target["title"] as? [String: String])?["key"] == "SAS-DB")
        #expect((target["subtitle"] as? [String: String])?["key"] == "sa@db.example.com:22")
        #expect((target["symbol"] as? [String: String])?["systemName"] == "terminal")

        // Must serialize as a property list for `shortcuts sign`.
        _ = try PropertyListSerialization.data(fromPropertyList: workflow, format: .binary, options: 0)
    }

    @Test func adHocBuildsLeaveOutTheTeam() throws {
        let connection = Connection(name: "A", host: "a", type: .rdp, username: "u")
        let workflow = ShortcutExport.workflow(for: ConnectionEntity(connection), bundleID: "com.example.app", teamID: nil)
        let actions = try #require(workflow["WFWorkflowActions"] as? [[String: Any]])
        let parameters = try #require(actions.first?["WFWorkflowActionParameters"] as? [String: Any])
        let descriptor = try #require(parameters["AppIntentDescriptor"] as? [String: Any])
        #expect(descriptor["TeamIdentifier"] == nil)
    }
}
