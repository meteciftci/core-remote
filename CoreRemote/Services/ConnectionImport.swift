import Foundation
import SwiftData

/// A connection found in an outside file, before the user decides to import it.
nonisolated struct ImportCandidate: Identifiable, Equatable, Sendable {
    let id = UUID()
    var name: String
    var host: String
    var type: ConnectionType
    var port: Int
    var username: String
    var keyFilePath: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        (lhs.name, lhs.host, lhs.type, lhs.port, lhs.username, lhs.keyFilePath)
            == (rhs.name, rhs.host, rhs.type, rhs.port, rhs.username, rhs.keyFilePath)
    }

    /// Host, port and user, compared without case, identify the same server login.
    var duplicateKey: String {
        Self.duplicateKey(host: host, port: port, username: username)
    }

    static func duplicateKey(host: String, port: Int, username: String) -> String {
        "\(username.lowercased())@\(host.lowercased()):\(port)"
    }
}

/// Reads `Host` entries from an OpenSSH client config (`~/.ssh/config`).
nonisolated enum SSHConfigParser {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh/config")
    }

    /// One candidate per concrete alias. Patterns (`*`, `?`, `!`) are skipped, `Match` blocks are
    /// ignored, and values from a `Host *` block fill in what an entry leaves out.
    static func parse(_ text: String, defaultUser: String = NSUserName()) -> [ImportCandidate] {
        struct Block {
            var aliases: [String]
            var options: [String: String] = [:]
        }

        var blocks: [Block] = []
        var current: Block?
        for rawLine in text.components(separatedBy: .newlines) {
            guard let (key, value) = keyValue(rawLine) else { continue }
            switch key {
            case "host":
                current.map { blocks.append($0) }
                current = Block(aliases: value.split(whereSeparator: \.isWhitespace).map { unquote(String($0)) })
            case "match":
                current.map { blocks.append($0) }
                current = nil
            default:
                // ssh uses the first value it sees for each option.
                if current?.options[key] == nil {
                    current?.options[key] = unquote(value)
                }
            }
        }
        current.map { blocks.append($0) }

        let defaults = blocks.first { $0.aliases == ["*"] }?.options ?? [:]
        return blocks.flatMap { block in
            block.aliases
                .filter { !$0.contains(where: { "*?!".contains($0) }) }
                .map { alias in
                    let options = block.options.merging(defaults) { own, _ in own }
                    return ImportCandidate(
                        name: alias,
                        host: options["hostname"].map { $0.replacingOccurrences(of: "%h", with: alias) } ?? alias,
                        type: .ssh,
                        port: options["port"].flatMap(Int.init).flatMap { (1...65535).contains($0) ? $0 : nil } ?? ConnectionType.ssh.defaultPort,
                        username: options["user"] ?? defaultUser,
                        keyFilePath: options["identityfile"]
                    )
                }
        }
    }

    /// Splits `Key value`, `Key=value` or `Key = value`; `nil` for blanks and comments.
    private static func keyValue(_ line: String) -> (String, String)? {
        let line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        guard let separator = line.firstIndex(where: { $0.isWhitespace || $0 == "=" }) else { return nil }
        let key = line[..<separator].lowercased()
        var value = line[separator...].drop { $0.isWhitespace }
        if value.first == "=" { value = value.dropFirst().drop { $0.isWhitespace } }
        guard !value.isEmpty else { return nil }
        return (key, String(value).trimmingCharacters(in: .whitespaces))
    }

    private static func unquote(_ value: String) -> String {
        value.count >= 2 && value.hasPrefix("\"") && value.hasSuffix("\"") ? String(value.dropFirst().dropLast()) : value
    }
}

/// Reads the server and user from a `.rdp` file.
nonisolated enum RDPFileParser {
    static func parse(_ data: Data, name: String) -> ImportCandidate? {
        guard let text = decode(data) else { return nil }
        var values: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            // Lines look like "full address:s:server:3389"; the value may contain colons.
            let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            values[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] = parts[2].trimmingCharacters(in: .whitespaces)
        }
        guard let address = values["full address"], !address.isEmpty else { return nil }

        var (host, port) = split(address)
        if port == nil, let serverPort = values["server port"].flatMap(Int.init) {
            port = serverPort
        }
        return ImportCandidate(
            name: name,
            host: host,
            type: .rdp,
            port: port.flatMap { (1...65535).contains($0) ? $0 : nil } ?? ConnectionType.rdp.defaultPort,
            username: values["username"] ?? "",
            keyFilePath: nil
        )
    }

    /// Windows saves `.rdp` files as UTF-16 with a byte order mark; others are UTF-8.
    private static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
    }

    /// `host`, `host:port`, `[v6]`, `[v6]:port`, or a bare IPv6 address.
    private static func split(_ address: String) -> (String, Int?) {
        if address.hasPrefix("["), let close = address.firstIndex(of: "]") {
            let host = String(address[address.index(after: address.startIndex)..<close])
            let rest = address[address.index(after: close)...]
            return (host, rest.hasPrefix(":") ? Int(rest.dropFirst()) : nil)
        }
        let colons = address.filter { $0 == ":" }.count
        if colons == 1, let colon = address.lastIndex(of: ":") {
            return (String(address[..<colon]), Int(address[address.index(after: colon)...]))
        }
        return (address, nil)
    }
}

// MARK: - Adding to the store

enum ConnectionImporter {
    /// Candidates that match an existing connection (or an earlier candidate) by host, port and user.
    static func duplicateIDs(in candidates: [ImportCandidate], existing: [Connection]) -> Set<UUID> {
        var seen = Set(existing.map { ImportCandidate.duplicateKey(host: $0.host, port: $0.port, username: $0.effectiveUsername) })
        var duplicates = Set<UUID>()
        for candidate in candidates where !seen.insert(candidate.duplicateKey).inserted {
            duplicates.insert(candidate.id)
        }
        return duplicates
    }

    @discardableResult
    static func add(_ candidates: [ImportCandidate], to group: ConnectionGroup?, in context: ModelContext) throws -> [Connection] {
        let connections = candidates.map { candidate in
            Connection(
                name: candidate.name,
                host: candidate.host,
                type: candidate.type,
                port: candidate.port,
                username: candidate.username,
                keyFilePath: candidate.keyFilePath,
                group: group
            )
        }
        connections.forEach(context.insert)
        try context.save()
        return connections
    }
}
