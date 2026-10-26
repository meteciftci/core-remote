import SwiftUI

nonisolated enum ConnectionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case ssh
    case rdp
    case serial

    var id: String { rawValue }

    /// `0` for serial, which has no port.
    var defaultPort: Int {
        switch self {
        case .ssh: 22
        case .rdp: 3389
        case .serial: 0
        }
    }

    /// SSH and RDP reach a server over the network; serial opens a local device.
    var usesNetwork: Bool { self != .serial }

    var title: String {
        switch self {
        case .ssh: "SSH"
        case .rdp: "RDP"
        case .serial: String(localized: "Serial")
        }
    }

    var symbol: String {
        switch self {
        case .ssh: "terminal"
        case .rdp: "display"
        case .serial: "cable.connector"
        }
    }

    var tint: Color {
        switch self {
        case .ssh: .orange
        case .rdp: .blue
        case .serial: .green
        }
    }
}
