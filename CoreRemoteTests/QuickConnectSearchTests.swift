import Foundation
import Testing
@testable import CoreRemote

@MainActor
struct QuickConnectSearchTests {
    private func connection(_ name: String, host: String = "h", user: String = "u", favorite: Bool = false, last: TimeInterval? = nil) -> Connection {
        let connection = Connection(name: name, host: host, type: .ssh, username: user, isFavorite: favorite)
        connection.lastConnectedAt = last.map(Date.init(timeIntervalSince1970:))
        return connection
    }

    @Test func emptyQueryShowsRecentThenFavoritesThenNames() {
        let all = [
            connection("Zeta"),
            connection("Alpha"),
            connection("Fav", favorite: true),
            connection("Old", last: 100),
            connection("New", last: 200),
        ]
        #expect(QuickConnectSearch.results(for: " ", in: all).map(\.name) == ["New", "Old", "Fav", "Alpha", "Zeta"])
    }

    @Test func namePrefixBeatsWordBeatsContainsBeatsHost() {
        let all = [
            connection("Web via host", host: "db-01"),
            connection("Old db server"),
            connection("Mydb"),
            connection("DB Primary"),
        ]
        #expect(QuickConnectSearch.results(for: "db", in: all).map(\.name) == ["DB Primary", "Old db server", "Mydb", "Web via host"])
    }

    @Test func recentBreaksTies() {
        let all = [connection("Server A"), connection("Server B", last: 10)]
        #expect(QuickConnectSearch.results(for: "server", in: all).map(\.name) == ["Server B", "Server A"])
    }

    @Test func matchesUserAndIgnoresDiacritics() {
        let all = [connection("Sunucu", user: "mete"), connection("Gölge")]
        #expect(QuickConnectSearch.results(for: "METE", in: all).map(\.name) == ["Sunucu"])
        #expect(QuickConnectSearch.results(for: "golge", in: all).map(\.name) == ["Gölge"])
        #expect(QuickConnectSearch.results(for: "nothing", in: all).isEmpty)
    }
}
