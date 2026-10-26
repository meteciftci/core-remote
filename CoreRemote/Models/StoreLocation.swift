import Foundation
import SQLite3

/// Where the connection store lives. Before 1.3.2 it was SwiftData's default,
/// `~/Library/Application Support/default.store`, a name any app can use and that
/// `brew uninstall --zap` couldn't remove. It now lives in CoreRemote's own folder.
nonisolated enum StoreLocation {
    static var url: URL {
        URL.applicationSupportDirectory.appending(path: "CoreRemote/CoreRemote.store")
    }

    static var legacyURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    /// SQLite keeps recent writes in these files next to the store.
    private static let companionSuffixes = ["", "-shm", "-wal"]

    /// Copies the old store to `url` the first time, if it's CoreRemote's. Returns true when it did;
    /// the old files are left for `removeLegacyStore(at:)` once the new store has opened.
    @discardableResult
    static func migrateLegacyStore(from legacy: URL = legacyURL, to url: URL = url) throws -> Bool {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: url.path), isCoreRemoteStore(legacy) else { return false }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            for suffix in companionSuffixes {
                let source = URL(filePath: legacy.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(at: source, to: URL(filePath: url.path + suffix))
            }
        } catch {
            // A half-copied store would be opened as the real one next time.
            for suffix in companionSuffixes {
                try? fileManager.removeItem(at: URL(filePath: url.path + suffix))
            }
            throw error
        }
        return true
    }

    static func removeLegacyStore(at legacy: URL = legacyURL) {
        for suffix in companionSuffixes {
            try? FileManager.default.removeItem(at: URL(filePath: legacy.path + suffix))
        }
    }

    /// Another app may own a `default.store`; CoreRemote's has its connection and group tables.
    static func isCoreRemoteStore(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return false }
        // A store that was just closed may still be locked while SQLite folds its log back in.
        sqlite3_busy_timeout(database, 2000)

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name IN ('ZCONNECTION', 'ZCONNECTIONGROUP')"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return false }
        return sqlite3_column_int(statement, 0) == 2
    }
}
