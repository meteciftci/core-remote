import Foundation
import SQLite3
import SwiftData
import Testing
@testable import CoreRemote

@MainActor
struct StoreLocationTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "StoreLocationTests-\(UUID().uuidString)")
    private var legacy: URL { folder.appending(path: "default.store") }
    private var store: URL { folder.appending(path: "CoreRemote/CoreRemote.store") }

    private func makeLegacyStore(named name: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(url: legacy))
        let context = ModelContext(container)
        context.insert(Connection(name: name, host: "web", type: .ssh, username: "deploy"))
        try context.save()
    }

    @Test func movesTheOldStoreAndRemovesIt() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try makeLegacyStore(named: "Web")

        let container = try AppSchema.container(at: store, legacy: legacy)

        let names = try ModelContext(container).fetch(FetchDescriptor<Connection>()).map(\.name)
        #expect(names == ["Web"])
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path + "-wal"))
    }

    @Test func keepsAStoreThatIsAlreadyMoved() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try makeLegacyStore(named: "Old")
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        let current = try ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(url: store))
        let context = ModelContext(current)
        context.insert(Connection(name: "Current", host: "pi", type: .ssh, username: "pi"))
        try context.save()

        #expect(try !StoreLocation.migrateLegacyStore(from: legacy, to: store))
        #expect(FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test func leavesOtherAppsStoresAlone() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var database: OpaquePointer?
        #expect(sqlite3_open(legacy.path, &database) == SQLITE_OK)
        sqlite3_exec(database, "CREATE TABLE ZNOTE (Z_PK INTEGER PRIMARY KEY)", nil, nil, nil)
        sqlite3_close(database)

        let container = try AppSchema.container(at: store, legacy: legacy)

        #expect(try ModelContext(container).fetch(FetchDescriptor<Connection>()).isEmpty)
        #expect(FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test func startsEmptyWithoutAnOldStore() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let container = try AppSchema.container(at: store, legacy: legacy)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Connection>()).isEmpty)
        #expect(FileManager.default.fileExists(atPath: store.path))
    }
}
