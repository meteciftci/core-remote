import AppKit
import Foundation
import Security
import SwiftData

/// `coreremote://connect/<connection id>` opens a saved connection, for links and scripts.
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

/// Makes a one-step shortcut that runs CoreRemote's "Connect" action for a connection, signs it
/// with macOS's `shortcuts` tool and opens it, so Kestirmeler only asks to confirm adding it.
/// macOS has no API to add a shortcut directly, and it refuses unsigned files.
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
    nonisolated static let intentIdentifier = "ConnectIntent"

    /// The unsigned shortcut, as a property list. The `target` dictionary is how Kestirmeler stores
    /// a picked `ConnectionEntity` (read from a shortcut made by hand in the app). `teamID` is nil
    /// for ad-hoc signed builds.
    nonisolated static func workflow(for entity: ConnectionEntity, bundleID: String, teamID: String?) -> [String: Any] {
        var descriptor: [String: Any] = [
            "AppIntentIdentifier": intentIdentifier,
            "BundleIdentifier": bundleID,
            "Name": "CoreRemote",
        ]
        descriptor["TeamIdentifier"] = teamID
        return [
            "WFWorkflowActions": [
                [
                    "WFWorkflowActionIdentifier": "\(bundleID).\(intentIdentifier)",
                    "WFWorkflowActionParameters": [
                        "AppIntentDescriptor": descriptor,
                        "UUID": UUID().uuidString,
                        "target": [
                            "identifier": entity.id.uuidString,
                            "title": ["key": entity.name],
                            "subtitle": ["key": entity.summary],
                            "symbol": ["systemName": entity.symbol],
                        ],
                    ],
                ],
            ],
            "WFWorkflowClientVersion": "5037.0.19",
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

    /// The shortcut's name, phrased so it can be said to Siri: "DC-1 bağlantısını aç".
    static func shortcutName(for connection: Connection) -> String {
        String(localized: "Connect to \(connection.name)")
    }

    /// The team that signed this build, or nil for ad-hoc signing.
    static var teamIdentifier: String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    static func addToShortcuts(_ connection: Connection) async throws {
        let directory = LaunchFiles.directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Kestirmeler names the imported shortcut after the file.
        let fileName = LaunchFiles.fileName(for: shortcutName(for: connection), extension: "shortcut")
        let unsigned = directory.appending(path: "unsigned.shortcut")
        let signed = directory.appending(path: fileName)

        let workflow = workflow(
            for: ConnectionEntity(connection),
            bundleID: Bundle.main.bundleIdentifier ?? "com.meteciftci.CoreRemote",
            teamID: teamIdentifier
        )
        let data = try PropertyListSerialization.data(fromPropertyList: workflow, format: .binary, options: 0)
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
