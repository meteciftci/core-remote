import Foundation

/// The `SSH_ASKPASS` program. ssh runs it with the prompt as its argument.
/// The first time it prints the password from the one-time file and deletes the file;
/// after that (for example a wrong password) it asks in the terminal instead.
enum AskpassHelper {
    static let script = """
        #!/bin/sh
        # CoreRemote SSH_ASKPASS helper.
        f="$COREREMOTE_PASSFILE"
        case "$1" in
          *yes/no*) ;;
          *)
            if [ -n "$f" ] && [ -f "$f" ]; then
              cat "$f"
              rm -f "$f"
              exit 0
            fi
            ;;
        esac
        printf '%s' "$1" > /dev/tty
        case "$1" in
          *yes/no*) IFS= read -r answer < /dev/tty ;;
          *)
            stty -echo < /dev/tty
            IFS= read -r answer < /dev/tty
            stty echo < /dev/tty
            printf '\\n' > /dev/tty
            ;;
        esac
        printf '%s\\n' "$answer"

        """

    /// Writes the helper to Application Support (refreshing it every time) and returns its path.
    static func install() throws -> URL {
        let url = LaunchFiles.askpassHelperURL
        try LaunchFiles.write(script, named: url.lastPathComponent, permissions: 0o700, in: url.deletingLastPathComponent())
        return url
    }
}
