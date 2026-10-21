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
    /// RDP only: connect even when the server certificate can't be verified.
    var ignoreCertificateErrors: Bool = false
    var isFavorite: Bool
    var createdAt: Date
    /// When the connection was last opened; `nil` if never (or after clearing history).
    var lastConnectedAt: Date?
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
        ignoreCertificateErrors: Bool = false,
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
        self.ignoreCertificateErrors = ignoreCertificateErrors
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
            keyFilePath: keyFilePath,
            ignoreCertificateErrors: ignoreCertificateErrors
        )
    }
}

extension Connection {
    /// Forgets when every connection was last opened.
    static func clearHistory(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<Connection>(predicate: #Predicate { $0.lastConnectedAt != nil })
        for connection in try context.fetch(descriptor) {
            connection.lastConnectedAt = nil
        }
        try context.save()
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
    var ignoreCertificateErrors = false
}
