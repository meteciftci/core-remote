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

/// The OpenSSH programs CoreRemote runs in a terminal.
nonisolated enum SSHProgram: Sendable {
    /// An interactive shell.
    case ssh
    /// File transfer.
    case sftp
}

nonisolated enum SSHCommand {
    /// The `ssh` or `sftp` invocation for a target, without any password handling.
    static func arguments(for target: ConnectionTarget, program: SSHProgram = .ssh) -> [String] {
        var arguments = switch program {
        case .ssh: ["ssh", "-p", String(target.port)]
        case .sftp: ["sftp", "-P", String(target.port)]
        }
        arguments += ["-o", "StrictHostKeyChecking=accept-new"]
        if let keyFilePath = target.keyFilePath, !keyFilePath.isEmpty {
            arguments += ["-i", (keyFilePath as NSString).expandingTildeInPath]
        }
        // sftp reads "host:path", so an IPv6 address needs brackets.
        let host = program == .sftp && target.host.contains(":") && !target.host.hasPrefix("[") ? "[\(target.host)]" : target.host
        // `--` keeps a host that starts with "-" from being read as an option.
        arguments += ["--", "\(target.username)@\(host)"]
        return arguments
    }

    /// A shell command line, optionally prefixed with the askpass environment.
    static func commandLine(for target: ConnectionTarget, program: SSHProgram = .ssh, askpass: AskpassEnvironment? = nil) -> String {
        let environment = askpass?.variables.map { "\($0.0)=\($0.1.shellQuoted)" } ?? []
        return (environment + arguments(for: target, program: program).map(\.shellQuoted)).joined(separator: " ")
    }

    /// The script a terminal app runs. When ssh or sftp fails to connect (exit code 255: refused,
    /// timed out, wrong password), it waits for a key so the error stays readable. iTerm2 closes
    /// the window as soon as the script ends.
    static func script(
        for target: ConnectionTarget,
        program: SSHProgram = .ssh,
        askpass: AskpassEnvironment?,
        failureMessage: String,
        closePrompt: String
    ) -> String {
        """
        #!/bin/zsh
        rm -f -- "$0"
        clear
        \(commandLine(for: target, program: program, askpass: askpass))
        code=$?
        if (( code == 255 )); then
          print -r -- ""
          print -r -- \(failureMessage.shellQuoted)" $code"
          print -rn -- \(closePrompt.shellQuoted)
          # Drop keys typed while ssh was connecting, so they don't close the window unread.
          while read -t 0.2 -sk 1; do :; done
          read -sk 1
        fi

        """
    }
}
