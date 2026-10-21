import AppIntents
import CoreSpotlight
import SwiftData

/// A saved connection as Shortcuts, Siri and Spotlight see it.
struct ConnectionEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Connection")
    static let defaultQuery = ConnectionQuery()

    let id: UUID
    let name: String
    let summary: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(summary)",
            image: DisplayRepresentation.Image(systemName: symbol)
        )
    }

    init(_ connection: Connection) {
        id = connection.id
        name = connection.name
        summary = connection.summary
        symbol = connection.type.symbol
    }
}

struct ConnectionQuery: EntityStringQuery {
    @Dependency private var container: ModelContainer

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ConnectionEntity] {
        try ConnectionEntityLookup.entities(for: identifiers, in: container.mainContext)
    }

    @MainActor
    func entities(matching string: String) async throws -> [ConnectionEntity] {
        try ConnectionEntityLookup.entities(matching: string, in: container.mainContext)
    }

    @MainActor
    func suggestedEntities() async throws -> [ConnectionEntity] {
        try ConnectionEntityLookup.entities(matching: "", in: container.mainContext)
    }
}

/// The store lookups behind `ConnectionQuery`, kept apart so they can be tested without App Intents.
enum ConnectionEntityLookup {
    static func entities(for identifiers: [UUID], in context: ModelContext) throws -> [ConnectionEntity] {
        let all = try context.fetch(FetchDescriptor<Connection>())
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0] }.map(ConnectionEntity.init)
    }

    /// Same ranking as the quick connect palette; an empty string lists recent connections first.
    static func entities(matching string: String, in context: ModelContext) throws -> [ConnectionEntity] {
        let all = try context.fetch(FetchDescriptor<Connection>(sortBy: [SortDescriptor(\.name)]))
        return QuickConnectSearch.results(for: string, in: all).map(ConnectionEntity.init)
    }
}

/// Connects to a saved connection. As an `OpenIntent` it also runs when a connection is picked
/// in Spotlight.
struct ConnectIntent: OpenIntent {
    static let title: LocalizedStringResource = "Connect"
    static let description = IntentDescription("Opens a saved SSH or RDP connection.")

    @Parameter(title: "Connection")
    var target: ConnectionEntity

    @Dependency private var container: ModelContainer
    @Dependency private var launcher: ConnectionLauncher

    static var parameterSummary: some ParameterSummary {
        Summary("Connect to \(\.$target)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let id = target.id
        guard let connection = try container.mainContext.fetch(FetchDescriptor<Connection>(predicate: #Predicate { $0.id == id })).first else {
            throw ConnectIntentError.notFound
        }
        await launcher.open(connection)
        if let problem = launcher.launchProblem {
            launcher.launchProblem = nil
            throw ConnectIntentError.launchFailed(problem)
        }
        return .result()
    }
}

enum ConnectIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notFound
    case launchFailed(LaunchProblem)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notFound:
            "This connection no longer exists."
        case .launchFailed(.missingClient(let client)):
            "\(client.title) is not installed"
        case .launchFailed(.failed(_, let message)):
            "\(message)"
        }
    }
}

struct CoreRemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConnectIntent(),
            phrases: [
                "Connect to \(\.$target) with \(.applicationName)",
                "Open \(\.$target) in \(.applicationName)",
                "\(.applicationName) connect to \(\.$target)",
            ],
            shortTitle: "Connect",
            systemImageName: "network"
        )
    }
}

/// Keeps Spotlight's copy of the connection list current.
enum SpotlightIndex {
    static func update(_ connections: [Connection]) async {
        #if DEBUG
        // Sample data must not replace the user's real connections in Spotlight.
        if DemoData.isEnabled { return }
        #endif
        let entities = connections.map(ConnectionEntity.init)
        do {
            try await CSSearchableIndex.default().deleteAppEntities(ofType: ConnectionEntity.self)
            try await CSSearchableIndex.default().indexAppEntities(entities)
        } catch {
            // Spotlight is a convenience; the app works the same without it.
        }
    }
}
