import Foundation

/// Short-lived files handed to Terminal, ssh and Windows App.
/// They live in the per-user temporary directory, which only this user can read.
enum LaunchFiles {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appending(path: "CoreRemote", directoryHint: .isDirectory)
    }

    static var askpassHelperURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "CoreRemote", directoryHint: .isDirectory)
            .appending(path: "askpass.sh")
    }

    /// Writes `contents` to a new file that only the owner can access.
    @discardableResult
    static func write(_ contents: String, named name: String, permissions: Int = 0o600, in directory: URL = directory) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appending(path: name)
        try? fileManager.removeItem(at: url)
        guard fileManager.createFile(atPath: url.path, contents: Data(contents.utf8), attributes: [.posixPermissions: permissions]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        return url
    }

    /// Deletes the file after a delay, if it is still there.
    static func remove(_ url: URL, after delay: Duration) {
        Task {
            try? await Task.sleep(for: delay)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Clears leftovers from earlier runs.
    static func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Makes a string safe to use as a file name.
    static func fileName(for name: String, extension ext: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/:\\\0\n\r")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Connection" : cleaned) + "." + ext
    }
}
