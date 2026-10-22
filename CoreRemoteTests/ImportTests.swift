import Foundation
import SwiftData
import Testing
@testable import CoreRemote

struct SSHConfigParserTests {
    private let config = """
        # Personal servers
        Host web web-alias
            HostName web-01.example.com
            User deploy
            Port 2222
            IdentityFile ~/.ssh/id_ed25519

        Host db
          hostname=db-01.example.com
          Port = 22
          User postgres
          User ignored-second-value

        Host *.internal !bastion
            User skipped

        Match host *.corp
            User skipped-too

        Host pi
            HostName "raspberrypi.local"

        Host *
            User fallback
            IdentityFile ~/.ssh/default
        """

    @Test func readsConcreteHostsAndAliases() {
        let candidates = SSHConfigParser.parse(config, defaultUser: "me")
        #expect(candidates.map(\.name) == ["web", "web-alias", "db", "pi"])

        let web = candidates[0]
        #expect(web.host == "web-01.example.com")
        #expect(web.port == 2222)
        #expect(web.username == "deploy")
        #expect(web.keyFilePath == "~/.ssh/id_ed25519")
        #expect(web.type == .ssh)
        #expect(candidates[1].host == "web-01.example.com")
    }

    @Test func handlesEqualsSyntaxAndFirstValueWins() {
        let db = SSHConfigParser.parse(config, defaultUser: "me")[2]
        #expect(db.host == "db-01.example.com")
        #expect(db.port == 22)
        #expect(db.username == "postgres")
    }

    @Test func fillsMissingValuesFromHostStar() {
        let pi = SSHConfigParser.parse(config, defaultUser: "me")[3]
        #expect(pi.host == "raspberrypi.local")
        #expect(pi.username == "fallback")
        #expect(pi.keyFilePath == "~/.ssh/default")
        #expect(pi.port == 22)
    }

    @Test func fallsBackToAliasAndDefaultUser() {
        let candidates = SSHConfigParser.parse("Host plain\n", defaultUser: "me")
        #expect(candidates.first?.host == "plain")
        #expect(candidates.first?.username == "me")
    }
}

struct RDPFileParserTests {
    @Test func readsAddressPortAndUser() throws {
        let text = "screen mode id:i:2\r\nfull address:s:win.example.com:3390\r\nusername:s:EXAMPLE\\admin\r\n"
        let candidate = try #require(RDPFileParser.parse(Data(text.utf8), name: "Win"))
        #expect(candidate.name == "Win")
        #expect(candidate.host == "win.example.com")
        #expect(candidate.port == 3390)
        #expect(candidate.username == "EXAMPLE\\admin")
        #expect(candidate.type == .rdp)
    }

    @Test func readsUTF16FilesFromWindows() throws {
        var data = Data([0xFF, 0xFE])
        data.append("full address:s:10.0.0.5\r\n".data(using: .utf16LittleEndian)!)
        let candidate = try #require(RDPFileParser.parse(data, name: "Old"))
        #expect(candidate.host == "10.0.0.5")
        #expect(candidate.port == 3389)
        #expect(candidate.username == "")
    }

    @Test func handlesIPv6AndServerPort() throws {
        let bracketed = try #require(RDPFileParser.parse(Data("full address:s:[fe80::1]:3391".utf8), name: "a"))
        #expect(bracketed.host == "fe80::1")
        #expect(bracketed.port == 3391)

        let bare = try #require(RDPFileParser.parse(Data("full address:s:fe80::2\nserver port:i:3392".utf8), name: "b"))
        #expect(bare.host == "fe80::2")
        #expect(bare.port == 3392)
    }

    @Test func rejectsFilesWithoutAddress() {
        #expect(RDPFileParser.parse(Data("username:s:x".utf8), name: "x") == nil)
    }
}

@MainActor
struct ConnectionImporterTests {
    @Test func flagsExistingAndRepeatedLogins() {
        let existing = [Connection(name: "Web", host: "WEB.example.com", type: .ssh, port: 22, username: "Deploy")]
        let same = ImportCandidate(name: "web", host: "web.example.com", type: .ssh, port: 22, username: "deploy")
        let otherPort = ImportCandidate(name: "web2", host: "web.example.com", type: .ssh, port: 2222, username: "deploy")
        let repeated = ImportCandidate(name: "web2 again", host: "web.example.com", type: .ssh, port: 2222, username: "deploy")

        let duplicates = ConnectionImporter.duplicateIDs(in: [same, otherPort, repeated], existing: existing)
        #expect(duplicates == [same.id, repeated.id])
    }

    @Test func addsConnectionsToGroup() throws {
        let container = try AppSchema.container(inMemory: true)
        let context = ModelContext(container)
        let group = ConnectionGroup(name: "Imported")
        context.insert(group)
        let candidate = ImportCandidate(name: "pi", host: "pi.local", type: .ssh, port: 22, username: "pi", keyFilePath: "~/.ssh/id")

        try ConnectionImporter.add([candidate], to: group, in: context)

        let connection = try #require(try context.fetch(FetchDescriptor<Connection>()).first)
        #expect(connection.name == "pi")
        #expect(connection.keyFilePath == "~/.ssh/id")
        #expect(connection.group?.name == "Imported")
    }
}
