import SwiftUI

nonisolated enum ConnectionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case ssh
    case rdp

    var id: String { rawValue }

    var defaultPort: Int {
        switch self {
        case .ssh: 22
        case .rdp: 3389
        }
    }

    var title: String {
        switch self {
        case .ssh: "SSH"
        case .rdp: "RDP"
        }
    }

    var symbol: String {
        switch self {
        case .ssh: "terminal"
        case .rdp: "display"
        }
    }

    var tint: Color {
        switch self {
        case .ssh: .orange
        case .rdp: .blue
        }
    }
}
