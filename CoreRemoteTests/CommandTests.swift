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
    }

    @Test func wrapsIPv6Hosts() {
        let contents = RDPFile.contents(for: target(host: "fe80::1", type: .rdp, port: 3390))
        #expect(contents.contains("full address:s:[fe80::1]:3390"))
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
