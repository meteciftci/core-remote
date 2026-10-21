import Foundation

/// Environment that lets ssh read the stored password through the askpass helper.
nonisolated struct AskpassEnvironment: Equatable, Sendable {
    var helperPath: String
    var passwordFilePath: String

    var variables: [(String, String)] {
        [
            ("SSH_ASKPASS", helperPath),
            ("SSH_ASKPASS_REQUIRE", "force"),
            ("COREREMOTE_PASSFILE", passwordFilePath),
        ]
    }
}

nonisolated enum SSHCommand {
    /// The `ssh` invocation for a target, without any password handling.
    static func arguments(for target: ConnectionTarget) -> [String] {
        var arguments = ["ssh", "-p", String(target.port), "-o", "StrictHostKeyChecking=accept-new"]
        if let keyFilePath = target.keyFilePath, !keyFilePath.isEmpty {
            arguments += ["-i", (keyFilePath as NSString).expandingTildeInPath]
        }
        // `--` keeps a host that starts with "-" from being read as an option.
        arguments += ["--", "\(target.username)@\(target.host)"]
        return arguments
    }

    /// A shell command line, optionally prefixed with the askpass environment.
    static func commandLine(for target: ConnectionTarget, askpass: AskpassEnvironment? = nil) -> String {
        let environment = askpass?.variables.map { "\($0.0)=\($0.1.shellQuoted)" } ?? []
        return (environment + arguments(for: target).map(\.shellQuoted)).joined(separator: " ")
    }
}
