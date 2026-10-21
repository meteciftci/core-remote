import Foundation
import Testing
@testable import CoreRemote

private func target(
    host: String = "10.0.0.5",
    type: ConnectionType = .ssh,
    port: Int? = nil,
    username: String = "mete",
    keyFilePath: String? = nil
) -> ConnectionTarget {
    ConnectionTarget(
        id: UUID(),
        name: "Test",
        host: host,
        type: type,
        port: port ?? type.defaultPort,
        username: username,
        keyFilePath: keyFilePath
    )
}

struct ShellQuotingTests {
    @Test(arguments: [
        ("simple", "simple"),
        ("/usr/bin/ssh", "/usr/bin/ssh"),
        ("user@host", "user@host"),
        ("with space", "'with space'"),
        ("it's", "'it'\\''s'"),
        ("$(rm -rf ~)", "'$(rm -rf ~)'"),
        ("", "''"),
    ])
    func quotes(input: String, expected: String) {
        #expect(input.shellQuoted == expected)
    }
}

struct SSHCommandTests {
    @Test func basicCommand() {
        #expect(SSHCommand.arguments(for: target()) == [
            "ssh", "-p", "22", "-o", "StrictHostKeyChecking=accept-new", "--", "mete@10.0.0.5",
        ])
    }

    @Test func customPortAndKey() throws {
        let args = SSHCommand.arguments(for: target(port: 2222, keyFilePath: "~/.ssh/id_ed25519"))
        #expect(args.contains("2222"))
        let keyIndex = try #require(args.firstIndex(of: "-i"))
        #expect(args[keyIndex + 1] == NSHomeDirectory() + "/.ssh/id_ed25519")
    }

    @Test func hostCannotInjectOptions() {
        let args = SSHCommand.arguments(for: target(host: "-oProxyCommand=evil"))
        #expect(args.suffix(2) == ["--", "mete@-oProxyCommand=evil"])
    }

    @Test func commandLineQuotesUnsafeValues() {
        let line = SSHCommand.commandLine(for: target(username: "a b"))
        #expect(line.hasSuffix("-- 'a b@10.0.0.5'"))
    }

    @Test func askpassEnvironmentComesFirst() {
        let askpass = AskpassEnvironment(helperPath: "/Users/x/Library/Application Support/CoreRemote/askpass.sh", passwordFilePath: "/tmp/p")
        let line = SSHCommand.commandLine(for: target(), askpass: askpass)
        #expect(line.hasPrefix("SSH_ASKPASS='/Users/x/Library/Application Support/CoreRemote/askpass.sh' SSH_ASKPASS_REQUIRE=force COREREMOTE_PASSFILE=/tmp/p ssh "))
        #expect(!line.contains("secret"))
    }
}

struct RDPFileTests {
    @Test func containsAddressAndUser() {
        let contents = RDPFile.contents(for: target(host: "win.local", type: .rdp, username: "admin"))
        #expect(contents.contains("full address:s:win.local:3389\r\n"))
        #expect(contents.contains("username:s:admin\r\n"))
        #expect(contents.contains("screen mode id:i:1\r\n"))
    }

    @Test func certificateWarningsFollowOption() {
        var rdp = target(type: .rdp)
        #expect(RDPFile.contents(for: rdp).contains("authentication level:i:2\r\n"))
        rdp.ignoreCertificateErrors = true
        #expect(RDPFile.contents(for: rdp).contains("authentication level:i:0\r\n"))
    }

    @Test func wrapsIPv6Hosts() {
        let contents = RDPFile.contents(for: target(host: "fe80::1", type: .rdp, port: 3390))
        #expect(contents.contains("full address:s:[fe80::1]:3390"))
    }
}

struct FreeRDPTests {
    @Test func argumentsWithPassword() {
        let args = FreeRDP.arguments(for: target(host: "win", type: .rdp, username: "CORP\\admin"), password: "p@ss word")
        #expect(args.contains("/v:win:3389"))
        #expect(args.contains("/u:CORP\\admin"))
        #expect(args.contains("/cert:tofu"))
        #expect(args.last == "/p:p@ss word")
    }

    @Test func noPasswordArgumentWithoutPassword() {
        var rdp = target(host: "fe80::1", type: .rdp)
        rdp.ignoreCertificateErrors = true
        let args = FreeRDP.arguments(for: rdp, password: nil)
        #expect(args.contains("/v:[fe80::1]:3389"))
        #expect(args.contains("/cert:ignore"))
        #expect(!args.contains { $0.hasPrefix("/p:") })
    }
}

struct LaunchFilesTests {
    @Test func fileNamesAreSanitized() {
        #expect(LaunchFiles.fileName(for: "a/b:c", extension: "rdp") == "a-b-c.rdp")
        #expect(LaunchFiles.fileName(for: "  ", extension: "command") == "Connection.command")
    }

    @Test func writtenFilesArePrivate() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try LaunchFiles.write("secret", named: "p", in: directory)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(try String(contentsOf: url, encoding: .utf8) == "secret")
    }

    @Test func askpassHelperUsesFileOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = try LaunchFiles.write(AskpassHelper.script, named: "askpass.sh", permissions: 0o700, in: directory)
        let passwordFile = try LaunchFiles.write("p@ss word", named: "pass", in: directory)

        let process = Process()
        process.executableURL = helper
        process.arguments = ["mete@host's password: "]
        process.environment = ["COREREMOTE_PASSFILE": passwordFile.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(output == "p@ss word")
        #expect(!FileManager.default.fileExists(atPath: passwordFile.path))
    }
}

struct FreeRDPWindowSizeTests {
    @Test func usesFixedSizeWithSmartSizing() {
        let args = FreeRDP.arguments(for: target(type: .rdp), password: nil)
        #expect(args.contains("/size:1280x800"))
        #expect(args.contains("+smart-sizing"))
        #expect(!args.contains("+dynamic-resolution"))
    }
}

struct TerminalAppTests {
    @Test func defaultsToTerminal() {
        #expect(TerminalApp.defaultApp == .terminal)
        #expect(TerminalApp.terminal.brewCommand == nil)
        #expect(TerminalApp.allCases.filter { $0 != .terminal }.allSatisfy { $0.brewCommand?.hasPrefix("brew install --cask ") == true })
    }
}

struct SSHScriptTests {
    @Test func waitsWhenSSHFails() throws {
        let script = SSHCommand.script(
            for: target(host: "127.0.0.1", port: 1),
            askpass: nil,
            failureMessage: "Closed. Code:",
            closePrompt: "Press a key."
        )
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).command")
        try script.write(to: url, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = [url.path]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(output.contains("Closed. Code: 255"))
        #expect(output.contains("Press a key."))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

struct ITerm2SessionTests {
    @Test func runsTheScriptInANewWindow() {
        let source = ITerm2Session.source(scriptPath: "/tmp/CoreRemote/Bir Hayat \"VPS\".command")
        #expect(source.contains(#"tell application id "com.googlecode.iterm2""#))
        #expect(source.contains(#"create window with default profile command "/bin/zsh '/tmp/CoreRemote/Bir Hayat \"VPS\".command'""#))
    }
}

struct FileTransferTests {
    @Test func sftpUsesCapitalPAndBracketsIPv6() {
        #expect(SSHCommand.arguments(for: target(port: 2222), program: .sftp) == [
            "sftp", "-P", "2222", "-o", "StrictHostKeyChecking=accept-new", "--", "mete@10.0.0.5",
        ])
        #expect(SSHCommand.arguments(for: target(host: "fe80::1"), program: .sftp).last == "mete@[fe80::1]")
        #expect(SSHCommand.arguments(for: target(host: "fe80::1")).last == "mete@fe80::1")
    }

    @Test func linkHasNoPassword() throws {
        let url = try #require(SFTPLink.url(for: target(port: 2222, username: "EXAMPLE\\mete")))
        #expect(url.absoluteString == "sftp://EXAMPLE%5Cmete@10.0.0.5:2222/")
        #expect(SFTPLink.url(for: target(host: "fe80::1"))?.absoluteString == "sftp://mete@[fe80::1]:22/")
    }

    @Test func storedChoiceRoundTrips() {
        for client in [FileTransferClient.automatic, .terminal, .app("ch.sudo.cyberduck")] {
            #expect(FileTransferClient(storedValue: client.storedValue) == client)
        }
    }
}
