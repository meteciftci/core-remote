import CommonCrypto
import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let coreRemoteBackup = UTType(exportedAs: "com.meteciftci.coreremote.backup", conformingTo: .json)
}

/// What a `.coreremote` file carries, before encryption.
nonisolated struct BackupPayload: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var host: String
        var type: ConnectionType
        var port: Int
        var username: String
        var keyFilePath: String?
        /// Missing in files from before this option existed.
        var ignoreCertificateErrors: Bool?
        var notes: String?
        var tags: [String]?
        var isFavorite: Bool
        var group: String?
        var password: String?
    }

    var groups: [String]
    var connections: [Item]

    var hasPasswords: Bool { connections.contains { $0.password != nil } }
}

nonisolated enum BackupError: LocalizedError, Equatable {
    case invalidFile
    case unsupportedVersion(Int)
    case passphraseRequired
    case wrongPassphrase

    var errorDescription: String? {
        switch self {
        case .invalidFile: String(localized: "This is not a CoreRemote backup file.")
        case .unsupportedVersion(let version): String(localized: "This backup was made by a newer version of CoreRemote (format \(version)).")
        case .passphraseRequired: String(localized: "This backup is encrypted. Enter its passphrase.")
        case .wrongPassphrase: String(localized: "The passphrase is incorrect.")
        }
    }
}

/// Reads and writes `.coreremote` files.
/// Passwords are only written when the file is encrypted with a passphrase
/// (AES-GCM, key derived with PBKDF2-SHA256).
nonisolated enum Backup {
    static let format = "coreremote"
    static let version = 1
    static let defaultIterations = 600_000

    private struct File: Codable {
        var format: String
        var version: Int
        var exportedAt: Date
        var payload: BackupPayload?
        var encrypted: Encrypted?
    }

    private struct Encrypted: Codable {
        var kdf = "PBKDF2-SHA256"
        var iterations: Int
        var salt: Data
        var sealedBox: Data
    }

    static func encode(_ payload: BackupPayload, passphrase: String?, iterations: Int = defaultIterations) throws -> Data {
        var file = File(format: format, version: version, exportedAt: .now)

        if let passphrase, !passphrase.isEmpty {
            let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
            let key = deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
            let sealed = try AES.GCM.seal(try encoder.encode(payload), using: key)
            guard let combined = sealed.combined else { throw BackupError.invalidFile }
            file.encrypted = Encrypted(iterations: iterations, salt: salt, sealedBox: combined)
        } else {
            var plain = payload
            for index in plain.connections.indices {
                plain.connections[index].password = nil
            }
            file.payload = plain
        }
        return try encoder.encode(file)
    }

    static func isEncrypted(_ data: Data) throws -> Bool {
        try readFile(data).encrypted != nil
    }

    static func decode(_ data: Data, passphrase: String?) throws -> BackupPayload {
        let file = try readFile(data)
        if let payload = file.payload { return payload }
        guard let encrypted = file.encrypted else { throw BackupError.invalidFile }
        guard let passphrase, !passphrase.isEmpty else { throw BackupError.passphraseRequired }

        let key = deriveKey(passphrase: passphrase, salt: encrypted.salt, iterations: encrypted.iterations)
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(try AES.GCM.SealedBox(combined: encrypted.sealedBox), using: key)
        } catch {
            throw BackupError.wrongPassphrase
        }
        do {
            return try decoder.decode(BackupPayload.self, from: plaintext)
        } catch {
            throw BackupError.invalidFile
        }
    }

    private static func readFile(_ data: Data) throws -> File {
        guard let file = try? decoder.decode(File.self, from: data), file.format == format else {
            throw BackupError.invalidFile
        }
        guard file.version <= version else { throw BackupError.unsupportedVersion(file.version) }
        return file
    }

    private static func deriveKey(passphrase: String, salt: Data, iterations: Int) -> SymmetricKey {
        let password = Array(passphrase.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        salt.withUnsafeBytes { saltBytes in
            _ = CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password.map { CChar(bitPattern: $0) }, password.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived, derived.count
            )
        }
        return SymmetricKey(data: derived)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - SwiftData bridge

struct ImportSummary: Equatable {
    var added = 0
    var skipped = 0
    var groupsCreated = 0
}

enum BackupStore {
    static func payload(
        connections: [Connection],
        groups: [ConnectionGroup],
        includePasswords: Bool,
        passwords: PasswordStore
    ) -> BackupPayload {
        BackupPayload(
            groups: groups.map(\.name).sorted(),
            connections: connections.map { connection in
                BackupPayload.Item(
                    id: connection.id,
                    name: connection.name,
                    host: connection.host,
                    type: connection.type,
                    port: connection.port,
                    username: connection.username,
                    keyFilePath: connection.keyFilePath,
                    ignoreCertificateErrors: connection.ignoreCertificateErrors,
                    notes: connection.notes.isEmpty ? nil : connection.notes,
                    tags: connection.tags.isEmpty ? nil : connection.tags,
                    isFavorite: connection.isFavorite,
                    group: connection.group?.name,
                    password: includePasswords ? passwords.password(for: connection.id) : nil
                )
            }
        )
    }

    /// Adds connections that aren't already present (matched by ID).
    /// Groups are matched by name, ignoring case, and created when missing.
    static func importPayload(_ payload: BackupPayload, into context: ModelContext, passwords: PasswordStore) throws -> ImportSummary {
        var summary = ImportSummary()
        let existingIDs = Set(try context.fetch(FetchDescriptor<Connection>()).map(\.id))
        var groupsByName: [String: ConnectionGroup] = [:]
        for group in try context.fetch(FetchDescriptor<ConnectionGroup>()) {
            groupsByName[group.name.lowercased()] = group
        }

        func group(named name: String?) -> ConnectionGroup? {
            guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            if let group = groupsByName[name.lowercased()] { return group }
            let group = ConnectionGroup(name: name)
            context.insert(group)
            groupsByName[name.lowercased()] = group
            summary.groupsCreated += 1
            return group
        }

        for name in payload.groups {
            _ = group(named: name)
        }

        for item in payload.connections {
            guard !existingIDs.contains(item.id) else {
                summary.skipped += 1
                continue
            }
            let connection = Connection(
                id: item.id,
                name: item.name,
                host: item.host,
                type: item.type,
                port: (1...65535).contains(item.port) ? item.port : item.type.defaultPort,
                username: item.username,
                keyFilePath: item.type == .ssh ? item.keyFilePath : nil,
                ignoreCertificateErrors: item.type == .rdp && item.ignoreCertificateErrors == true,
                notes: item.notes ?? "",
                tags: Tags.normalize(item.tags ?? []),
                isFavorite: item.isFavorite,
                group: group(named: item.group)
            )
            context.insert(connection)
            if let password = item.password {
                try passwords.setPassword(password, for: item.id)
            }
            summary.added += 1
        }

        try context.save()
        return summary
    }
}
