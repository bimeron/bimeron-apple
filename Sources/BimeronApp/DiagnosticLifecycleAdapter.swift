import BimeronDaemon

/// Consumes observations only; constructing this adapter does not connect to a service.
struct DiagnosticLifecycleAdapter {
    private(set) var state: LifecycleState = .unknown

    mutating func observe(_ state: LifecycleState) -> DiagnosticEvent {
        self.state = state
        let outcome: DiagnosticEvent.Outcome
        switch state {
        case .unknown: outcome = .unknown
        case .stopped: outcome = .stopped
        case .connecting: outcome = .connecting
        case .connected: outcome = .connected
        case .reconnecting: outcome = .reconnecting
        case .failed: outcome = .failed
        case .starting: outcome = .starting
        case .stopping: outcome = .stopping
        case .cleanupUnconfirmed: outcome = .cleanupUnconfirmed
        }
        return DiagnosticEvent(source: .lifecycle, kind: .observation, outcome: outcome, attemptID: nil)
    }

    mutating func lostIPC() -> DiagnosticEvent {
        state = .unknown
        return DiagnosticEvent(source: .lifecycle, kind: .ipc, outcome: .unknown, attemptID: nil)
    }
}
