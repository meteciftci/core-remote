import AppKit
import Foundation
import SwiftData

/// `coreremote://connect/<connection id>` opens a saved connection. Kestirmeler (Shortcuts)
/// files made by `ShortcutExport` use it.
enum ConnectURL {
    nonisolated static let scheme = "coreremote"

    nonisolated static func url(for id: UUID) -> URL {
        URL(string: "\(scheme)://connect/\(id.uuidString)")!
    }

    nonisolated static func connectionID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == "connect" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    /// Connects to the connection a URL names. Problems show in a standalone alert,
    /// since a URL can arrive while no window is open.
    static func handle(_ url: URL, container: ModelContainer, launcher: ConnectionLauncher) async {
        guard let id = connectionID(from: url) else { return }
        let descriptor = FetchDescriptor<Connection>(predicate: #Predicate { $0.id == id })
        guard let connection = try? container.mainContext.fetch(descriptor).first else {
            LaunchProblemAlert.run(.failed(name: "", message: String(localized: "This connection no longer exists.")), launcher: launcher)
            return
        }
        await launcher.open(connection)
        if let problem = launcher.launchProblem {
            launcher.launchProblem = nil
            LaunchProblemAlert.run(problem, launcher: launcher)
        }
    }
}

/// Makes a one-step shortcut ("open coreremote://connect/…") for a connection, signs it with
/// macOS's `shortcuts` tool and opens it, so Kestirmeler only asks to confirm adding it.
/// macOS has no API to add a shortcut directly, and it refuses unsigned shortcut files.
enum ShortcutExport {
    enum ExportError: LocalizedError {
        case signingFailed(String)

        var errorDescription: String? {
            switch self {
            case .signingFailed(let output):
                String(localized: "The shortcut couldn't be signed. Signing needs an internet connection and an iCloud account.\n\n\(output)")
            }
        }
    }

    static let shortcutsTool = URL(filePath: "/usr/bin/shortcuts")

    /// The unsigned shortcut, as a property list.
    nonisolated static func workflow(for id: UUID) -> [String: Any] {
        [
            "WFWorkflowActions": [
                [
                    "WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
                    "WFWorkflowActionParameters": ["WFInput": ConnectURL.url(for: id).absoluteString],
                ],
            ],
            "WFWorkflowClientVersion": "2607.0.2",
            "WFWorkflowIcon": [
                "WFWorkflowIconStartColor": 431_817_727, // blue
                "WFWorkflowIconGlyphNumber": 59_511,
            ],
            "WFWorkflowImportQuestions": [Any](),
            "WFWorkflowInputContentItemClasses": [Any](),
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowTypes": [Any](),
        ]
    }

    static func addToShortcuts(_ connection: Connection) async throws {
        let directory = LaunchFiles.directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Kestirmeler names the imported shortcut after the file.
        let fileName = LaunchFiles.fileName(for: connection.name, extension: "shortcut")
        let unsigned = directory.appending(path: "unsigned.shortcut")
        let signed = directory.appending(path: fileName)

        let data = try PropertyListSerialization.data(fromPropertyList: workflow(for: connection.id), format: .binary, options: 0)
        try data.write(to: unsigned)
        try await sign(unsigned, to: signed)
        LaunchFiles.remove(directory, after: .seconds(300))
        NSWorkspace.shared.open(signed)
    }

    private static func sign(_ input: URL, to output: URL) async throws {
        let process = Process()
        process.executableURL = shortcutsTool
        process.arguments = ["sign", "--mode", "anyone", "--input", input.path, "--output", output.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        let message = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard status == 0, FileManager.default.fileExists(atPath: output.path) else {
            throw ExportError.signingFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
