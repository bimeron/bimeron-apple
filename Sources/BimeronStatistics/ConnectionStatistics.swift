import Foundation

/// Normalized in-memory inputs, deliberately independent of the daemon wire format.
public struct ConnectionStatistics: Sendable {
    public struct Identity: Equatable, Sendable {
        public let instance: String
        public let session: String
        public init(instance: String, session: String) {
            self.instance = instance; self.session = session
        }
    }
    public struct Token: Equatable, Sendable {
        public let identity: Identity
        fileprivate let generation: UUID
    }
    public enum Status: Sendable { case unknown, disconnected, connecting, connected, reconnecting, stopping, failed }
    public struct Counters: Equatable, Sendable {
        public let bytesUp: Int64
        public let bytesDown: Int64
        public init(bytesUp: Int64, bytesDown: Int64) {
            self.bytesUp = bytesUp; self.bytesDown = bytesDown
        }
    }
    public struct Rate: Equatable, Sendable {
        public let bytesUpPerSecond: Double
        public let bytesDownPerSecond: Double
    }
    public struct Sample: Equatable, Sendable {
        public let elapsed: Duration
        public let counters: Counters?
        public let rate: Rate?
    }
    /// Events have instance/generation scope only; they do not identify a session.
    public struct Event: Equatable, Sendable {
        public let sequence: UInt64
        public let code: String
        public init(sequence: UInt64, code: String) { self.sequence = sequence; self.code = code }
    }
    public let staleAfter: Duration
    public let historyLimit: Int
    public let eventLimit: Int
    public private(set) var token: Token?
    public private(set) var status: Status = .unknown
    public private(set) var latest: Sample?
    public private(set) var history: [Sample] = []
    public private(set) var events: [Event] = []
    public private(set) var cursor: UInt64 = 0
    public private(set) var needsResync = true
    private var baseline: Sample?
    private var lastSequence: UInt64?
    private var now: Duration = .zero

    public init(staleAfter: Duration, historyLimit: Int, eventLimit: Int) {
        precondition(staleAfter > .zero && historyLimit >= 0 && eventLimit >= 0)
        self.staleAfter = staleAfter; self.historyLimit = historyLimit; self.eventLimit = eventLimit
    }

    /// Call only after independently confirming the status/stats identity association.
    @discardableResult
    public mutating func confirm(_ identity: Identity) -> Token {
        precondition(!identity.instance.isEmpty && !identity.session.isEmpty)
        let next = Token(identity: identity, generation: UUID())
        token = next; status = .unknown; latest = nil; baseline = nil
        lastSequence = nil; history = []; events = []; cursor = 0; needsResync = false
        return next
    }

    public mutating func loseIPC() {
        token = nil; status = .unknown; latest = nil; baseline = nil; needsResync = true
    }

    /// Advance using elapsed time from one monotonic origin, including idle periods.
    @discardableResult
    public mutating func advance(to elapsed: Duration) -> Bool {
        guard elapsed >= now else { return false }
        now = elapsed
        if let latest, elapsed - latest.elapsed >= staleAfter {
            self.latest = nil; baseline = nil
        }
        return true
    }

    /// Sequence is caller-issued request ordering, not a Core statistics sequence.
    @discardableResult
    public mutating func observe(token: Token, sequence: UInt64, at elapsed: Duration,
                                 status: Status, counters: Counters?) -> Bool {
        guard token == self.token, !needsResync, elapsed >= now,
              lastSequence.map({ sequence > $0 }) ?? true,
              latest.map({ elapsed > $0.elapsed }) ?? true else { return false }
        advance(to: elapsed)
        lastSequence = sequence
        let valid = counters.flatMap { $0.bytesUp >= 0 && $0.bytesDown >= 0 ? $0 : nil }
        var rate: Rate?
        if self.status == .connected, status == .connected, let baseline, let old = baseline.counters,
           let valid, valid.bytesUp >= old.bytesUp, valid.bytesDown >= old.bytesDown {
            let parts = (elapsed - baseline.elapsed).components
            let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
            if seconds > 0 {
                rate = Rate(bytesUpPerSecond: Double(valid.bytesUp - old.bytesUp) / seconds,
                            bytesDownPerSecond: Double(valid.bytesDown - old.bytesDown) / seconds)
            }
        }
        self.status = status
        let sample = Sample(elapsed: elapsed, counters: valid, rate: rate)
        latest = sample
        baseline = status == .connected && valid != nil ? sample : nil
        history.append(sample)
        history = Array(history.suffix(historyLimit))
        return true
    }

    /// A dropped batch invalidates confirmation; authoritative status must be reread.
    @discardableResult
    public mutating func observeEvents(token: Token, cursor: UInt64, dropped: Bool, events: [Event]) -> Bool {
        guard token == self.token, !needsResync, cursor >= self.cursor,
              events.allSatisfy({ $0.sequence > self.cursor && $0.sequence <= cursor }),
              zip(events, events.dropFirst()).allSatisfy({ $0.sequence < $1.sequence }) else { return false }
        self.cursor = cursor
        self.events = Array((self.events + events).suffix(eventLimit))
        if dropped { loseIPC() }
        return true
    }
}
