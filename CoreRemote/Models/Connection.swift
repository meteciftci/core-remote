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
    /// Free-form notes shown in the editor and searched.
    var notes: String = ""
    /// Labels such as "prod" or "dc"; see `Tags.normalize`.
    var tags: [String] = []
    var isFavorite: Bool
    var createdAt: Date
    /// Position in the manual list order; ties (such as connections from before manual order
    /// existed) fall back to the name. See `ConnectionOrder`.
    var sortIndex: Int = 0
    /// When the connection was last opened; `nil` if never (or after clearing history).
    var lastConnectedAt: Date?
    var group: ConnectionGroup?
    /// When set, the profile's user name, password and key file are used instead of this
    /// connection's own.
    var credentialProfile: CredentialProfile?

    // RDP only; `nil` uses the default from Settings. See `RDPOverrides`.
    var rdpDisplayRaw: String?
    var rdpMultiMonitor: Bool?
    var rdpClipboard: Bool?
    var rdpSharedFolder: String?
    var rdpAudioRaw: String?

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
        notes: String = "",
        tags: [String] = [],
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
        self.notes = notes
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.group = group
    }

    var rdpOverrides: RDPOverrides {
        get {
            RDPOverrides(
                display: rdpDisplayRaw.flatMap(RDPDisplay.init(rawValue:)),
                multiMonitor: rdpMultiMonitor,
                clipboard: rdpClipboard,
                sharedFolder: rdpSharedFolder,
                audio: rdpAudioRaw.flatMap(RDPAudio.init(rawValue:))
            )
        }
        set {
            rdpDisplayRaw = newValue.display?.rawValue
            rdpMultiMonitor = newValue.multiMonitor
            rdpClipboard = newValue.clipboard
            rdpSharedFolder = newValue.sharedFolder
            rdpAudioRaw = newValue.audio?.rawValue
        }
    }

    /// The user name a session logs in with: the profile's, or the connection's own.
    var effectiveUsername: String {
        credentialProfile?.username ?? username
    }

    var effectiveKeyFilePath: String? {
        guard type == .ssh else { return nil }
        if let profile = credentialProfile { return profile.keyFilePath }
        return keyFilePath
    }

    /// The Keychain entry holding the password: the profile's, or the connection's own.
    var passwordID: UUID {
        credentialProfile?.id ?? id
    }

    /// `user@host:port`, shown under the name in lists.
    var summary: String {
        "\(effectiveUsername)@\(host):\(port)"
    }

    var target: ConnectionTarget {
        ConnectionTarget(
            id: id,
            name: name,
            host: host,
            type: type,
            port: port,
            username: effectiveUsername,
            keyFilePath: effectiveKeyFilePath,
            passwordID: passwordID,
            ignoreCertificateErrors: ignoreCertificateErrors,
            rdp: type == .rdp ? RDPDefaults.load().applying(rdpOverrides) : RDPOptions()
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
    /// Where the password is kept; `nil` means under `id`.
    var passwordID: UUID?
    var ignoreCertificateErrors = false
    var rdp = RDPOptions()

    var keychainID: UUID { passwordID ?? id }
}
