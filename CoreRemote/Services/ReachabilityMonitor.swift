import AppKit
import SwiftUI

/// Keeps the latest reachability result per `host:port`, so connections that share a server
/// are checked once. For a serial connection it tells whether the device is plugged in.
@Observable
final class ReachabilityMonitor {
    enum Status: Equatable {
        case checking
        case reachable(latency: Duration)
        case unreachable(reason: String)
        /// A serial connection's device is plugged in.
        case deviceConnected
    }

    static let storageKey = "checksReachability"
    static let refreshInterval: Duration = .seconds(60)
    static let maxConcurrentChecks = 8

    private(set) var statuses: [String: Status] = [:]

    static func key(host: String, port: Int) -> String {
        "\(host.lowercased()):\(port)"
    }

    func status(for connection: Connection) -> Status? {
        statuses[Self.key(host: connection.host, port: connection.port)]
    }

    /// Checks every distinct server. Earlier results stay visible while a check runs;
    /// servers seen for the first time show as checking.
    func refresh(_ connections: [Connection]) async {
        var targets: [String: (host: String, port: Int)] = [:]
        var devices: [String: String] = [:]
        for connection in connections {
            let key = Self.key(host: connection.host, port: connection.port)
            if connection.type.usesNetwork {
                targets[key] = (connection.host, connection.port)
            } else {
                devices[key] = connection.host
            }
        }
        #if DEBUG
        if DemoData.isEnabled {
            statuses = targets.mapValues { DemoData.reachability(for: $0.host) }
                .merging(devices.mapValues { _ in .deviceConnected }) { $1 }
            return
        }
        #endif

        statuses = statuses.filter { targets[$0.key] != nil }
        for (key, path) in devices {
            statuses[key] = SerialDevices.isPresent(path)
                ? .deviceConnected
                : .unreachable(reason: String(localized: "Not connected"))
        }
        for key in targets.keys where statuses[key] == nil {
            statuses[key] = .checking
        }

        await withTaskGroup(of: (String, Reachability.Result).self) { group in
            var pending = targets.makeIterator()
            func addNext() -> Bool {
                guard let (key, target) = pending.next() else { return false }
                group.addTask { (key, await Reachability.check(host: target.host, port: target.port)) }
                return true
            }
            for _ in 0..<Self.maxConcurrentChecks {
                if !addNext() { break }
            }
            for await (key, result) in group {
                statuses[key] = switch result {
                case .reachable(let latency): .reachable(latency: latency)
                case .unreachable(let reason): .unreachable(reason: reason)
                }
                _ = addNext()
            }
        }
    }

    func reset() {
        statuses = [:]
    }
}

/// Refreshes `monitor` while the view exists: every minute, when the app comes to the front,
/// and right away when a server is added or changed. Kept out of `ContentView` so the setting
/// it reads doesn't re-render the whole window.
struct ReachabilityRefresh: ViewModifier {
    var monitor: ReachabilityMonitor
    var connections: [Connection]

    @AppStorage(ReachabilityMonitor.storageKey) private var isEnabled = true
    @State private var activations = 0

    private var taskID: String {
        let servers = Set(connections.map { ReachabilityMonitor.key(host: $0.host, port: $0.port) }).sorted()
        return "\(isEnabled)|\(activations)|\(servers.joined(separator: ","))"
    }

    func body(content: Content) -> some View {
        content
            .task(id: taskID) {
                guard isEnabled else {
                    monitor.reset()
                    return
                }
                while !Task.isCancelled {
                    await monitor.refresh(connections)
                    try? await Task.sleep(for: ReachabilityMonitor.refreshInterval)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                activations += 1
            }
    }
}
