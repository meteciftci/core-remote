import Foundation
import Network
import Testing
@testable import CoreRemote

struct ReachabilityTests {
    /// Starts a TCP listener on a random local port and returns it once it is ready.
    private func makeListener() async throws -> NWListener {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            listener.stateUpdateHandler = { state in
                if case .ready = state {
                    listener.stateUpdateHandler = nil
                    continuation.resume()
                }
            }
            listener.start(queue: .global())
        }
        return listener
    }

    @Test func openPortIsReachable() async throws {
        let listener = try await makeListener()
        defer { listener.cancel() }
        let port = try #require(listener.port?.rawValue)

        let result = await Reachability.check(host: "127.0.0.1", port: Int(port))
        guard case .reachable = result else {
            Issue.record("expected reachable, got \(result)")
            return
        }
    }

    @Test func closedPortIsRefused() async throws {
        // Grab a free port, then close it again so nothing listens there.
        let listener = try await makeListener()
        let port = try #require(listener.port?.rawValue)
        listener.cancel()
        try await Task.sleep(for: .milliseconds(100))

        let result = await Reachability.check(host: "127.0.0.1", port: Int(port))
        #expect(result == .unreachable(reason: String(localized: "Connection refused")))
    }

    @Test func invalidPortIsRejected() async {
        #expect(await Reachability.check(host: "127.0.0.1", port: 0) == .unreachable(reason: String(localized: "Invalid port")))
    }

    @Test func blackholedAddressTimesOut() async {
        // 192.0.2.0/24 is reserved for documentation and never answers.
        let result = await Reachability.check(host: "192.0.2.1", port: 22, timeout: .milliseconds(300))
        guard case .unreachable = result else {
            Issue.record("expected unreachable, got \(result)")
            return
        }
    }
}
