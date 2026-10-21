import Foundation
import SwiftData

@Model
final class Connection {
    @Attribute(.unique) var id: UUID
    var name: String
    var host: String
    var typeRaw: String
    var port: Int
    var username: String
    /// Absolute path to an SSH private key. Ignored for RDP.
    var keyFilePath: String?
    var isFavorite: Bool
    var createdAt: Date
    var group: ConnectionGroup?

    var type: ConnectionType {
        get { ConnectionType(rawValue: typeRaw) ?? .ssh }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        type: ConnectionType,
        port: Int? = nil,
        username: String,
        keyFilePath: String? = nil,
        isFavorite: Bool = false,
        createdAt: Date = .now,
        group: ConnectionGroup? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.typeRaw = type.rawValue
        self.port = port ?? type.defaultPort
        self.username = username
        self.keyFilePath = keyFilePath
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.group = group
    }

    /// `user@host:port`, shown under the name in lists.
    var summary: String {
        "\(username)@\(host):\(port)"
    }

    var target: ConnectionTarget {
        ConnectionTarget(
            id: id,
            name: name,
            host: host,
            type: type,
            port: port,
            username: username,
            keyFilePath: keyFilePath
        )
    }
}

/// Value snapshot of a connection, used by the launchers so they don't touch SwiftData.
nonisolated struct ConnectionTarget: Equatable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var type: ConnectionType
    var port: Int
    var username: String
    var keyFilePath: String?
}
