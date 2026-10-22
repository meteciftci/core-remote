import Foundation
import SwiftData

/// A user name, password and optional SSH key shared by several connections, such as a domain
/// account. The password is in the Keychain under the profile's `id`.
@Model
final class CredentialProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var username: String
    /// Absolute path to an SSH private key; used by SSH connections only.
    var keyFilePath: String?
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Connection.credentialProfile)
    var connections: [Connection] = []

    init(id: UUID = UUID(), name: String, username: String, keyFilePath: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.username = username
        self.keyFilePath = keyFilePath
        self.createdAt = createdAt
    }
}

extension CredentialProfile {
    /// Deletes the profile and its password. Connections that used it keep its user name and
    /// key file as their own, so they still open; their password has to be entered again.
    @MainActor
    static func delete(_ profile: CredentialProfile, in context: ModelContext, passwords: PasswordStore) throws {
        for connection in profile.connections {
            connection.username = profile.username
            if connection.type == .ssh, connection.keyFilePath == nil {
                connection.keyFilePath = profile.keyFilePath
            }
            connection.credentialProfile = nil
        }
        try passwords.setPassword(nil, for: profile.id)
        context.delete(profile)
        try context.save()
    }
}

/// Every model in the store, for each `ModelContainer`.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [Connection.self, ConnectionGroup.self, CredentialProfile.self]

    static func container(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(for: Schema(models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        return try container(at: StoreLocation.url, legacy: StoreLocation.legacyURL)
    }

    /// Opens the store at `url`, first moving a store left at `legacy` by an older version.
    static func container(at url: URL, legacy: URL) throws -> ModelContainer {
        let migrated = try StoreLocation.migrateLegacyStore(from: legacy, to: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let container = try ModelContainer(for: Schema(models), configurations: ModelConfiguration(url: url))
        if migrated {
            StoreLocation.removeLegacyStore(at: legacy)
        }
        return container
    }
}
