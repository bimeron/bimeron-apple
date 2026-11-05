import Foundation
import BimeronDaemon

/// Read-only, injected Core v1 observer. Never pairs legacy stats with separate status.
public actor DaemonStatisticsAdapter {
    public typealias Transport = DaemonClient.FramedExchange
    private let transport: Transport
    private let elapsed: @Sendable () -> Duration
    public private(set) var statistics: ConnectionStatistics
    private var inFlight = false
    private var sequence: UInt64 = 0

    /// Transport must bound receive buffering and enforce its own I/O deadline.
    /// One poll owns at most one exchange at a time; no background polling is started.
    public init(statistics: ConnectionStatistics, transport: @escaping Transport,
                elapsed: @escaping @Sendable () -> Duration) {
        self.statistics = statistics
        self.transport = transport
        self.elapsed = elapsed
    }

    public init(statistics: ConnectionStatistics, transport: @escaping Transport) {
        let clock = ContinuousClock()
        let origin = clock.now
        self.statistics = statistics
        self.transport = transport
        self.elapsed = { origin.duration(to: clock.now) }
    }

    /// The caller supplies an independently confirmed daemon/session identity, never an event or Attempt.
    public func confirm(_ identity: ConnectionStatistics.Identity) {
        guard !identity.instance.isEmpty, !identity.session.isEmpty else { invalidate(); return }
        statistics.confirm(identity)
    }

    public func invalidate() { statistics.loseIPC() }

    /// Advance even during idle periods or a pending exchange to expire displayed data.
    public func advance() { statistics.advance(to: elapsed()) }

    @discardableResult
    public func poll() async -> Bool {
        guard !inFlight, let token = statistics.token else { return false }
        let started = elapsed()
        guard statistics.advance(to: started) else { return false }
        inFlight = true
        defer { inFlight = false }
        sequence += 1
        let order = sequence
        do {
            try Task.checkCancellation()
            let hello = try await exchange("hello")
            guard statistics.token == token else { return false }
            guard hello.error == nil, hello.session_bound_stats == true,
                  hello.instance == token.identity.instance else { throw DaemonError.invalidProtocol }
            let response = try await exchange("stats_snapshot")
            guard statistics.token == token else { return false }
            let completed = elapsed()
            guard completed >= started, completed - started < statistics.staleAfter,
                  statistics.advance(to: completed), response.error == nil,
                  response.instance == token.identity.instance,
                  let snapshot = response.stats_snapshot,
                  snapshot.status.Session?.id == token.identity.session,
                  let status = Self.status(snapshot.status.State) else { throw DaemonError.invalidProtocol }
            let counters: ConnectionStatistics.Counters?
            if let wire = snapshot.counters {
                guard wire.bytes_up >= 0, wire.bytes_down >= 0 else { throw DaemonError.invalidProtocol }
                counters = wire.unavailable == true ? nil : .init(bytesUp: wire.bytes_up, bytesDown: wire.bytes_down)
            } else {
                counters = nil
            }
            return statistics.observe(token: token, sequence: order, at: completed, status: status, counters: counters)
        } catch {
            // An older exchange must not invalidate a newer caller confirmation.
            if statistics.token == token { statistics.loseIPC() }
            return false
        }
    }

    private func exchange(_ command: String) async throws -> DaemonResponse {
        try Task.checkCancellation()
        let request = DaemonRequest(command: command)
        _ = try DaemonProtocol.encode(request)
        let data = try await transport(request)
        try Task.checkCancellation()
        return try DaemonProtocol.decode(data, request: request)
    }

    private static func status(_ state: String) -> ConnectionStatistics.Status? {
        switch state {
        case "disconnected": .disconnected
        case "connecting": .connecting
        case "connected": .connected
        case "reconnecting": .reconnecting
        case "stopping": .stopping
        case "failed": .failed
        default: nil
        }
    }
}
