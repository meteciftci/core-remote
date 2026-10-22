import Foundation

/// Editable copy of a connection used by the editor sheet.
struct ConnectionDraft: Equatable {
    var name = ""
    var host = ""
    private(set) var type: ConnectionType = .ssh
    var port: Int? = ConnectionType.ssh.defaultPort
    var username = ""
    var password = ""
    var keyFilePath = ""
    /// A shared profile replaces the user name, password and key file below.
    var credentialProfileID: UUID?
    var ignoreCertificateErrors = false
    var rdp = RDPOverrides()
    var notes = ""
    /// Comma-separated, as typed in the editor.
    var tagsText = ""
    var isFavorite = false
    var groupID: UUID?

    init() {}

    init(connection: Connection, password: String?) {
        name = connection.name
        host = connection.host
        type = connection.type
        port = connection.port
        username = connection.username
        self.password = password ?? ""
        keyFilePath = connection.keyFilePath ?? ""
        credentialProfileID = connection.credentialProfile?.id
        ignoreCertificateErrors = connection.ignoreCertificateErrors
        rdp = connection.rdpOverrides
        notes = connection.notes
        tagsText = connection.tags.joined(separator: ", ")
        isFavorite = connection.isFavorite
        groupID = connection.group?.id
    }

    /// Changes the type and moves the port to the new default,
    /// unless the user typed a custom port.
    mutating func setType(_ newType: ConnectionType) {
        guard newType != type else { return }
        if port == nil || port == type.defaultPort {
            port = newType.defaultPort
        }
        type = newType
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedKeyFilePath: String? {
        let path = keyFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return type == .ssh && !path.isEmpty ? path : nil
    }

    var isPortValid: Bool {
        guard let port else { return false }
        return (1...65535).contains(port)
    }

    var isHostValid: Bool {
        !trimmedHost.isEmpty && !trimmedHost.contains(where: \.isWhitespace)
    }

    var usesProfile: Bool { credentialProfileID != nil }

    var isValid: Bool {
        !trimmedName.isEmpty && isHostValid && (usesProfile || !trimmedUsername.isEmpty) && isPortValid
    }

    /// The password to keep under the connection's own Keychain entry; none with a profile.
    var ownPassword: String? { usesProfile ? nil : password }

    func apply(to connection: Connection, group: ConnectionGroup?, profile: CredentialProfile? = nil) {
        connection.name = trimmedName
        connection.host = trimmedHost
        connection.type = type
        connection.port = port ?? type.defaultPort
        connection.username = trimmedUsername
        connection.keyFilePath = trimmedKeyFilePath
        connection.ignoreCertificateErrors = type == .rdp && ignoreCertificateErrors
        connection.rdpOverrides = type == .rdp ? rdp : RDPOverrides()
        connection.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        connection.tags = Tags.normalize(tagsText)
        connection.isFavorite = isFavorite
        connection.group = group
        connection.credentialProfile = profile
    }
}
