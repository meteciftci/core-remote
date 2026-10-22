import Foundation
import SwiftData
import Testing
@testable import CoreRemote

@MainActor
struct ConnectionOrderTests {
    private func connection(_ name: String, index: Int = 0, lastConnected: TimeInterval? = nil) -> Connection {
        let connection = Connection(name: name, host: name, type: .ssh, username: "u")
        connection.sortIndex = index
        connection.lastConnectedAt = lastConnected.map { Date(timeIntervalSinceReferenceDate: $0) }
        return connection
    }

    @Test func manualFallsBackToNameForTies() {
        let list = [connection("b"), connection("a"), connection("c", index: -1)]
        #expect(ConnectionOrder.sorted(list, by: .manual).map(\.name) == ["c", "a", "b"])
        #expect(ConnectionOrder.sorted(list, by: .name).map(\.name) == ["a", "b", "c"])
    }

    @Test func recentPutsNeverUsedLast() {
        let list = [connection("never"), connection("old", lastConnected: 1), connection("new", lastConnected: 2)]
        #expect(ConnectionOrder.sorted(list, by: .recent).map(\.name) == ["new", "old", "never"])
    }

    @Test func reorderingAFilteredListKeepsHiddenRowsInPlace() {
        let ids = (0..<5).map { _ in UUID() }
        // Visible: rows 1, 3 and 4. Drag row 4 to the top of the visible list.
        let visible = [ids[1], ids[3], ids[4]]
        let order = ConnectionOrder.reorder(all: ids, visible: visible, from: [2], to: 0)
        #expect(order == [ids[0], ids[4], ids[2], ids[1], ids[3]])
    }

    @Test func applyNumbersConnectionsInOrder() {
        let a = connection("a"), b = connection("b")
        ConnectionOrder.apply([b.id, a.id], to: [a, b])
        #expect(b.sortIndex == 0)
        #expect(a.sortIndex == 1)
    }

    @Test func newConnectionsGoLast() throws {
        let context = ModelContext(try AppSchema.container(inMemory: true))
        #expect(ConnectionOrder.nextIndex(in: context) == 0)
        context.insert(connection("a", index: 4))
        try context.save()
        #expect(ConnectionOrder.nextIndex(in: context) == 5)
    }
}
