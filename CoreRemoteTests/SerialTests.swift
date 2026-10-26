import Darwin
import Foundation
import SwiftData
import Testing
@testable import CoreRemote

struct SerialOptionsTests {
    @Test func defaultIs9600_8N1() {
        let options = SerialOptions()
        #expect(options.summary == "9600 8N1")
        #expect(options.isValid)
    }

    @Test func summaryShowsLineSettings() {
        let options = SerialOptions(baudRate: 115200, dataBits: 7, parity: .even, stopBits: 2)
        #expect(options.summary == "115200 7E2")
    }

    @Test func rejectsOutOfRangeValues() {
        #expect(!SerialOptions(baudRate: 0).isValid)
        #expect(!SerialOptions(dataBits: 9).isValid)
        #expect(!SerialOptions(stopBits: 3).isValid)
    }

    @Test func listsOnlyCUDevicesThatAreNotBuiltIn() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["cu.usbserial-2", "cu.usbserial-1", "tty.usbserial-1", "cu.Bluetooth-Incoming-Port", "cu.debug-console"] {
            FileManager.default.createFile(atPath: directory.appending(path: name).path, contents: nil)
        }
        #expect(SerialDevices.available(in: directory.path) == [
            "\(directory.path)/cu.usbserial-1",
            "\(directory.path)/cu.usbserial-2",
        ])
    }
}

struct SerialConnectionTests {
    @Test func draftNeedsNoUserOrPort() {
        var draft = ConnectionDraft()
        draft.setType(.serial)
        draft.name = "Switch"
        draft.host = "/dev/cu.usbserial-1"
        #expect(draft.port == 0)
        #expect(draft.isValid)
        draft.serial.baudRate = 0
        #expect(!draft.isValid)
    }

    @Test func applyKeepsSerialSettingsAndDropsLogin() {
        var draft = ConnectionDraft()
        draft.setType(.serial)
        draft.name = "Switch"
        draft.host = "/dev/cu.usbserial-1"
        draft.username = "admin"
        draft.password = "secret"
        draft.credentialProfileID = UUID()
        draft.serial = SerialOptions(baudRate: 115200, flowControl: .rtsCts)

        let connection = Connection(name: "", host: "", type: .ssh, username: "")
        draft.apply(to: connection, group: nil, profile: CredentialProfile(name: "P", username: "p"))
        #expect(connection.type == .serial)
        #expect(connection.port == 0)
        #expect(connection.username.isEmpty)
        #expect(connection.credentialProfile == nil)
        #expect(draft.ownPassword == nil)
        #expect(connection.serial == draft.serial)
        #expect(connection.summary == "/dev/cu.usbserial-1 · 115200 8N1")
        #expect(connection.target.serial == draft.serial)
    }

    @Test func switchingAwayClearsSerialSettings() {
        let connection = Connection(name: "Switch", host: "/dev/cu.usbserial-1", type: .serial, username: "")
        connection.serial = SerialOptions(baudRate: 115200)
        var draft = ConnectionDraft(connection: connection, password: nil)
        draft.setType(.ssh)
        draft.host = "switch.example.com"
        draft.username = "admin"
        draft.apply(to: connection, group: nil)
        #expect(connection.port == 22)
        #expect(connection.serialBaudRate == nil)
    }

    @Test func backupRoundTripsSerialSettings() throws {
        let container = try AppSchema.container(inMemory: true)
        let connection = Connection(name: "Switch", host: "/dev/cu.usbserial-1", type: .serial, username: "")
        let options = SerialOptions(baudRate: 57600, dataBits: 7, parity: .odd, stopBits: 2, flowControl: .xonXoff)
        connection.serial = options
        let payload = BackupStore.payload(connections: [connection], groups: [], includePasswords: false, passwords: InMemoryPasswordStore())

        let context = ModelContext(container)
        _ = try BackupStore.importPayload(payload, into: context, passwords: InMemoryPasswordStore())
        let imported = try #require(try context.fetch(FetchDescriptor<Connection>()).first)
        #expect(imported.type == .serial)
        #expect(imported.host == "/dev/cu.usbserial-1")
        #expect(imported.serial == options)
    }
}

struct SerialConsoleTests {
    @Test func argumentsRoundTrip() throws {
        let options = SerialOptions(baudRate: 921600, dataBits: 7, parity: .even, stopBits: 2, flowControl: .rtsCts)
        let arguments = SerialConsole.arguments(device: "/dev/cu.usbserial-1", options: options)
        #expect(arguments.first == SerialConsole.flag)
        let parsed = try #require(SerialConsole.parse(Array(arguments.dropFirst())))
        #expect(parsed.device == "/dev/cu.usbserial-1")
        #expect(parsed.options == options)
    }

    @Test func parseRejectsBadArguments() {
        #expect(SerialConsole.parse(["/dev/cu.x", "9600", "9", "none", "1", "none"]) == nil)
        #expect(SerialConsole.parse(["/dev/cu.x", "9600", "8", "mark", "1", "none"]) == nil)
        #expect(SerialConsole.parse(["/dev/cu.x"]) == nil)
    }

    @Test func configuresLineSettings() {
        var attributes = termios()
        SerialConsole.configure(&attributes, for: SerialOptions(baudRate: 115200, dataBits: 7, parity: .odd, stopBits: 2, flowControl: .rtsCts))
        #expect(attributes.c_cflag & tcflag_t(CSIZE) == tcflag_t(CS7))
        #expect(attributes.c_cflag & tcflag_t(PARENB | PARODD) == tcflag_t(PARENB | PARODD))
        #expect(attributes.c_cflag & tcflag_t(CSTOPB) != 0)
        #expect(attributes.c_cflag & tcflag_t(CCTS_OFLOW | CRTS_IFLOW) == tcflag_t(CCTS_OFLOW | CRTS_IFLOW))
        #expect(attributes.c_iflag & tcflag_t(IXON) == 0)
        #expect(cfgetospeed(&attributes) == 115200)

        SerialConsole.configure(&attributes, for: SerialOptions(flowControl: .xonXoff))
        #expect(attributes.c_cflag & tcflag_t(CSIZE) == tcflag_t(CS8))
        #expect(attributes.c_cflag & tcflag_t(PARENB | CSTOPB | CCTS_OFLOW) == 0)
        #expect(attributes.c_iflag & tcflag_t(IXON | IXOFF) == tcflag_t(IXON | IXOFF))
    }

    @Test func unusualSpeedIsLeftToTheIoctl() {
        var attributes = termios()
        SerialConsole.configure(&attributes, for: SerialOptions(baudRate: 921600))
        #expect(cfgetospeed(&attributes) == 9600)
    }

    @Test func ctrlACommands() {
        var escaping = false
        #expect(SerialConsole.interpret(Array("ls\r".utf8), escaping: &escaping) == [.send(Array("ls\r".utf8))])
        #expect(SerialConsole.interpret([0x61, 0x01, 0x01, 0x62], escaping: &escaping) == [.send([0x61, 0x01, 0x62])])
        #expect(SerialConsole.interpret([0x61, 0x01, 0x62, 0x63], escaping: &escaping) == [.send([0x61]), .sendBreak, .send([0x63])])
        #expect(SerialConsole.interpret([0x01, 0x71, 0x61], escaping: &escaping) == [.quit])
        #expect(SerialConsole.interpret([0x01, 0x78], escaping: &escaping) == [.send([0x01, 0x78])])
    }

    @Test func ctrlASpansReads() {
        var escaping = false
        #expect(SerialConsole.interpret([0x61, 0x01], escaping: &escaping) == [.send([0x61])])
        #expect(escaping)
        #expect(SerialConsole.interpret([0x51], escaping: &escaping) == [.quit])
    }

    @Test func scriptRunsTheConsoleAndWaitsAfterAnError() {
        let script = SerialConsole.script(
            executable: "/Applications/Core Remote.app/Contents/MacOS/CoreRemote",
            device: "/dev/cu.usbserial-1",
            options: SerialOptions(),
            closePrompt: "Press any key."
        )
        #expect(script.contains("'/Applications/Core Remote.app/Contents/MacOS/CoreRemote' --serial-console /dev/cu.usbserial-1 9600 8 none 1 none"))
        #expect(script.contains("if (( $? != 0 )); then"))
    }

    @Test func missingDeviceExplainsItself() {
        let missing = SerialConsole.openFailure(device: "/dev/cu.x", error: ENOENT)
        let busy = SerialConsole.openFailure(device: "/dev/cu.x", error: EBUSY)
        #expect(missing == String(localized: "\("/dev/cu.x") isn't connected."))
        #expect(busy.contains("/dev/cu.x"))
        #expect(busy != missing)
    }
}
