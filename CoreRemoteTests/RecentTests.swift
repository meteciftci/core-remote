import Foundation
import SwiftData
import Testing
@testable import CoreRemote

@MainActor
struct RecentTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Connection.self, ConnectionGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func recentIsNewestFirstAndSkipsNeverOpened() {
        let old = Connection(name: "Old", host: "a", type: .ssh, username: "u")
        let new = Connection(name: "New", host: "b", type: .ssh, username: "u")
        let never = Connection(name: "Never", host: "c", type: .rdp, username: "u")
        old.lastConnectedAt = Date(timeIntervalSince1970: 100)
        new.lastConnectedAt = Date(timeIntervalSince1970: 200)

        #expect(SidebarItem.recent.filter([never, old, new]).map(\.name) == ["New", "Old"])
    }

    @Test func recentIsLimited() {
        let connections = (0..<15).map { index in
            let connection = Connection(name: "C\(index)", host: "h", type: .ssh, username: "u")
            connection.lastConnectedAt = Date(timeIntervalSince1970: Double(index))
            return connection
        }
        let recent = SidebarItem.recent.filter(connections)
        #expect(recent.count == SidebarItem.recentLimit)
        #expect(recent.first?.name == "C14")
    }

    @Test func otherItemsKeepOrder() {
        let a = Connection(name: "A", host: "a", type: .ssh, username: "u", isFavorite: true)
        let b = Connection(name: "B", host: "b", type: .rdp, username: "u")
        #expect(SidebarItem.favorites.filter([a, b]).map(\.name) == ["A"])
        #expect(SidebarItem.type(.rdp).filter([a, b]).map(\.name) == ["B"])
        #expect(SidebarItem.all.filter([a, b]).map(\.name) == ["A", "B"])
    }

    @Test func clearHistoryKeepsConnections() throws {
        let context = try makeContext()
        let connection = Connection(name: "A", host: "a", type: .ssh, username: "u")
        connection.lastConnectedAt = .now
        context.insert(connection)
        try context.save()

        try Connection.clearHistory(in: context)

        let all = try context.fetch(FetchDescriptor<Connection>())
        #expect(all.count == 1)
        #expect(all.first?.lastConnectedAt == nil)
    }
}
