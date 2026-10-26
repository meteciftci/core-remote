import Foundation

nonisolated enum SerialParity: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case odd
    case even

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .odd: String(localized: "Odd")
        case .even: String(localized: "Even")
        }
    }

    /// The letter in "8N1".
    var letter: String {
        switch self {
        case .none: "N"
        case .odd: "O"
        case .even: "E"
        }
    }
}

nonisolated enum SerialFlowControl: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case rtsCts
    case xonXoff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .rtsCts: "RTS/CTS"
        case .xonXoff: "XON/XOFF"
        }
    }
}

/// The line settings a serial connection opens with, as in PuTTY. The default is 9600 8N1.
nonisolated struct SerialOptions: Equatable, Codable, Sendable {
    var baudRate = 9600
    var dataBits = 8
    var parity = SerialParity.none
    var stopBits = 1
    var flowControl = SerialFlowControl.none

    static let commonBaudRates = [300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]
    static let dataBitChoices = [5, 6, 7, 8]
    static let stopBitChoices = [1, 2]
    static let baudRateRange = 50...4_000_000

    var isValid: Bool {
        Self.baudRateRange.contains(baudRate) && Self.dataBitChoices.contains(dataBits) && Self.stopBitChoices.contains(stopBits)
    }

    /// "115200 8N1", shown in lists.
    var summary: String {
        "\(baudRate) \(dataBits)\(parity.letter)\(stopBits)"
    }
}

/// The serial ports macOS has right now, such as USB adapters.
nonisolated enum SerialDevices {
    static let directory = "/dev"
    /// Ports every Mac has, which aren't cables.
    static let builtIn: Set = ["cu.debug-console", "cu.Bluetooth-Incoming-Port"]

    /// `cu.*` rather than `tty.*`: opening a `tty` device waits for the other end's carrier signal.
    static func available(in directory: String = directory) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names
            .filter { $0.hasPrefix("cu.") && !builtIn.contains($0) }
            .sorted()
            .map { "\(directory)/\($0)" }
    }

    static func isPresent(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
