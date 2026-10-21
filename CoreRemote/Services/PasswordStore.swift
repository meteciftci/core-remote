import Foundation
import Security

/// Stores connection passwords outside SwiftData, keyed by connection ID.
protocol PasswordStore {
    func password(for id: UUID) -> String?
    func setPassword(_ password: String?, for id: UUID) throws
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return String(localized: "Keychain error: \(message)")
        }
    }
}

struct KeychainPasswordStore: PasswordStore {
    static let shared = KeychainPasswordStore()

    var service = "com.meteciftci.CoreRemote"

    private func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }

    func password(for id: UUID) -> String? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves the password; `nil` or an empty string removes it.
    func setPassword(_ password: String?, for id: UUID) throws {
        let query = baseQuery(for: id)

        guard let password, !password.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(status)
            }
            return
        }

        let data = Data(password.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "CoreRemote"
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }
}

/// In-memory store for tests and previews.
final class InMemoryPasswordStore: PasswordStore {
    private(set) var passwords: [UUID: String] = [:]

    func password(for id: UUID) -> String? { passwords[id] }

    func setPassword(_ password: String?, for id: UUID) throws {
        passwords[id] = (password?.isEmpty ?? true) ? nil : password
    }
}
