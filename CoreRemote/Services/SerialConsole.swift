import Darwin
import Foundation

/// A small serial terminal. The terminal app runs CoreRemote's own executable with `flag`, which
/// opens the device with every PuTTY line setting (macOS's `screen` can't set parity, stop bits
/// or RTS/CTS) and passes bytes both ways until Ctrl-A Q.
nonisolated enum SerialConsole {
    static let flag = "--serial-console"
    /// Ctrl-A starts a command, as in screen and picocom.
    static let escapeKey: UInt8 = 0x01
    /// Speeds termios takes directly; others are set with `IOSSIOSPEED`.
    static let termiosBaudRates: Set = [50, 75, 110, 134, 150, 200, 300, 600, 1200, 1800, 2400, 4800, 7200, 9600,
                                        14400, 19200, 28800, 38400, 57600, 76800, 115200, 230400]
    /// `_IOW('T', 2, speed_t)` from IOKit/serial/ioss.h, which Swift doesn't import.
    static let ioctlSetSpeed: UInt = 0x8008_5402
    /// `_IO('t', 13)`: no one else may open the device while it's in use.
    static let ioctlExclusive: UInt = 0x2000_740D

    static func arguments(device: String, options: SerialOptions) -> [String] {
        [
            flag, device, String(options.baudRate), String(options.dataBits),
            options.parity.rawValue, String(options.stopBits), options.flowControl.rawValue,
        ]
    }

    /// The script the terminal app runs. When the console stops with an error, such as an
    /// unplugged cable, it waits for a key so the message stays readable.
    static func script(executable: String, device: String, options: SerialOptions, closePrompt: String) -> String {
        let command = ([executable] + arguments(device: device, options: options)).map(\.shellQuoted).joined(separator: " ")
        return """
            #!/bin/zsh
            rm -f -- "$0"
            clear
            \(command)
            if (( $? != 0 )); then
              print -rn -- \(closePrompt.shellQuoted)
              while read -t 0.2 -sk 1; do :; done
              read -sk 1
            fi

            """
    }

    /// Reads what `arguments(device:options:)` wrote, without the flag.
    static func parse(_ arguments: [String]) -> (device: String, options: SerialOptions)? {
        guard arguments.count == 6,
              let baudRate = Int(arguments[1]),
              let dataBits = Int(arguments[2]),
              let parity = SerialParity(rawValue: arguments[3]),
              let stopBits = Int(arguments[4]),
              let flowControl = SerialFlowControl(rawValue: arguments[5])
        else { return nil }
        let options = SerialOptions(baudRate: baudRate, dataBits: dataBits, parity: parity, stopBits: stopBits, flowControl: flowControl)
        return options.isValid && !arguments[0].isEmpty ? (arguments[0], options) : nil
    }

    /// Raw mode with the given line settings.
    static func configure(_ attributes: inout termios, for options: SerialOptions) {
        cfmakeraw(&attributes)
        attributes.c_cflag &= ~tcflag_t(CSIZE | PARENB | PARODD | CSTOPB | CCTS_OFLOW | CRTS_IFLOW)
        attributes.c_cflag |= tcflag_t(CREAD | CLOCAL)
        let size = switch options.dataBits {
        case 5: CS5
        case 6: CS6
        case 7: CS7
        default: CS8
        }
        attributes.c_cflag |= tcflag_t(size)
        switch options.parity {
        case .none: break
        case .odd: attributes.c_cflag |= tcflag_t(PARENB | PARODD)
        case .even: attributes.c_cflag |= tcflag_t(PARENB)
        }
        if options.stopBits == 2 {
            attributes.c_cflag |= tcflag_t(CSTOPB)
        }
        attributes.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        switch options.flowControl {
        case .none: break
        case .rtsCts: attributes.c_cflag |= tcflag_t(CCTS_OFLOW | CRTS_IFLOW)
        case .xonXoff: attributes.c_iflag |= tcflag_t(IXON | IXOFF)
        }
        let speed = termiosBaudRates.contains(options.baudRate) ? options.baudRate : 9600
        cfsetspeed(&attributes, speed_t(speed))
    }

    /// What typed bytes do: most go to the device; Ctrl-A starts a command.
    enum Input: Equatable {
        case send([UInt8])
        case sendBreak
        case quit
    }

    /// Splits typed bytes into what to send and commands. `escaping` carries a Ctrl-A typed at
    /// the end of one read over to the next.
    static func interpret(_ bytes: some Sequence<UInt8>, escaping: inout Bool) -> [Input] {
        var inputs: [Input] = []
        var pending: [UInt8] = []
        func flush() {
            if !pending.isEmpty { inputs.append(.send(pending)) }
            pending = []
        }
        for byte in bytes {
            guard escaping else {
                if byte == escapeKey { escaping = true } else { pending.append(byte) }
                continue
            }
            escaping = false
            switch byte {
            case escapeKey:
                pending.append(escapeKey)
            case UInt8(ascii: "q"), UInt8(ascii: "Q"), 0x11:
                flush()
                inputs.append(.quit)
                return inputs
            case UInt8(ascii: "b"), UInt8(ascii: "B"), 0x02:
                flush()
                inputs.append(.sendBreak)
            default:
                pending += [escapeKey, byte]
            }
        }
        flush()
        return inputs
    }

    // MARK: - Running

    /// Runs the console and returns the exit code: 0 after Ctrl-A Q, 1 when the device can't be
    /// opened or goes away.
    static func run(_ arguments: [String]) -> Int32 {
        guard let (device, options) = parse(arguments) else {
            report(String(localized: "The serial settings are invalid."))
            return 1
        }
        let fd = open(device, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            report(openFailure(device: device, error: errno))
            return 1
        }
        defer { close(fd) }
        _ = ioctl(fd, ioctlExclusive)
        // Non-blocking was only so open doesn't wait for a carrier signal.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)

        var attributes = termios()
        tcgetattr(fd, &attributes)
        configure(&attributes, for: options)
        guard tcsetattr(fd, TCSANOW, &attributes) == 0 else {
            report(String(localized: "\(device) doesn't support these settings."))
            return 1
        }
        if !termiosBaudRates.contains(options.baudRate) {
            var speed = speed_t(options.baudRate)
            guard withUnsafeMutablePointer(to: &speed, { ioctl(fd, ioctlSetSpeed, $0) }) == 0 else {
                report(String(localized: "\(device) doesn't support \(String(options.baudRate)) baud."))
                return 1
            }
        }
        tcflush(fd, TCIOFLUSH)

        print(String(localized: "Connected to \(device) at \(options.summary)."))
        print(String(localized: "Ctrl-A Q quits · Ctrl-A B sends a break · Ctrl-A Ctrl-A sends Ctrl-A"))
        print("")
        fflush(stdout)

        // The terminal passes every key through, Ctrl-C included, and shows the device's output as is.
        var original = termios()
        let isTerminal = isatty(STDIN_FILENO) == 1 && tcgetattr(STDIN_FILENO, &original) == 0
        if isTerminal {
            var raw = original
            cfmakeraw(&raw)
            tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        }

        let ended = relay(device: fd)
        if isTerminal { tcsetattr(STDIN_FILENO, TCSANOW, &original) }
        switch ended {
        case .quit:
            print("")
            return 0
        case .deviceGone:
            print("")
            report(String(localized: "\(device) was disconnected."))
            return 1
        }
    }

    private enum Ending { case quit, deviceGone }

    private static func relay(device fd: Int32) -> Ending {
        var descriptors = [
            pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0),
            pollfd(fd: fd, events: Int16(POLLIN), revents: 0),
        ]
        var buffer = [UInt8](repeating: 0, count: 4096)
        var escaping = false
        let closed = Int16(POLLHUP | POLLERR | POLLNVAL)

        while true {
            guard poll(&descriptors, 2, -1) >= 0 else {
                if errno == EINTR { continue }
                return .deviceGone
            }
            if descriptors[1].revents & (Int16(POLLIN) | closed) != 0 {
                let count = read(fd, &buffer, buffer.count)
                if count < 0, errno == EAGAIN || errno == EINTR { continue }
                guard count > 0 else { return .deviceGone }
                writeAll(STDOUT_FILENO, buffer[..<count])
            }
            if descriptors[0].revents & (Int16(POLLIN) | closed) != 0 {
                let count = read(STDIN_FILENO, &buffer, buffer.count)
                if count < 0, errno == EAGAIN || errno == EINTR { continue }
                guard count > 0 else { return .quit }
                for input in interpret(buffer[..<count], escaping: &escaping) {
                    switch input {
                    case .send(let bytes): writeAll(fd, bytes[...])
                    case .sendBreak: tcsendbreak(fd, 0)
                    case .quit: return .quit
                    }
                }
            }
        }
    }

    private static func writeAll(_ fd: Int32, _ bytes: ArraySlice<UInt8>) {
        var remaining = bytes
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return
            }
            remaining = remaining.dropFirst(written)
        }
    }

    static func openFailure(device: String, error: Int32) -> String {
        switch error {
        case ENOENT, ENXIO: String(localized: "\(device) isn't connected.")
        case EBUSY: String(localized: "\(device) is in use by another app.")
        case EACCES, EPERM: String(localized: "CoreRemote isn't allowed to open \(device).")
        default: String(localized: "\(device) can't be opened: \(String(cString: strerror(error)))")
        }
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
