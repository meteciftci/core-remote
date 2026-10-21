import Foundation
import Network
import Synchronization

/// Checks whether a server accepts TCP connections on its port. ICMP ping isn't used
/// because many servers don't answer it while their SSH or RDP port is open.
nonisolated enum Reachability {
    enum Result: Equatable, Sendable {
        case reachable(latency: Duration)
        case unreachable(reason: String)
    }

    static let defaultTimeout: Duration = .seconds(2)

    static func check(host: String, port: Int, timeout: Duration = defaultTimeout) async -> Result {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)), port > 0 else {
            return .unreachable(reason: String(localized: "Invalid port"))
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "com.meteciftci.CoreRemote.reachability")
        let start = ContinuousClock.now
        let finished = Mutex(false)

        return await withCheckedContinuation { continuation in
            @Sendable func finish(_ result: Result) {
                let isFirst = finished.withLock { done in
                    defer { done = true }
                    return !done
                }
                guard isFirst else { return }
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.reachable(latency: ContinuousClock.now - start))
                // NWConnection waits and retries on refusals and DNS errors; one attempt is enough here.
                case .waiting(let error), .failed(let error):
                    finish(.unreachable(reason: describe(error)))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout.timeInterval) {
                finish(.unreachable(reason: String(localized: "Timed out")))
            }
        }
    }

    static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(.ECONNREFUSED):
            String(localized: "Connection refused")
        case .posix(.EHOSTUNREACH), .posix(.ENETUNREACH), .posix(.EHOSTDOWN):
            String(localized: "Host unreachable")
        case .posix(.ETIMEDOUT):
            String(localized: "Timed out")
        case .dns:
            String(localized: "Host not found")
        default:
            error.localizedDescription
        }
    }
}

extension Duration {
    nonisolated var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
