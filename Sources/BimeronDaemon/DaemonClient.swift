import Foundation

/// Serializes user intent and discards responses from invalidated exchanges.
public actor DaemonClient {
    public typealias Exchange = @Sendable (DaemonRequest) async throws -> DaemonResponse
    private let exchange: Exchange
    private var lifecycle = DaemonLifecycle()
    private var generation = 0
    private var operation: Task<DaemonResponse, Error>?

    public init() {
        exchange = { try await DaemonSocketTransport().exchange($0) }
    }

    /// Injection is for deterministic local adapters; it does not authenticate a daemon.
    public init(exchange: @escaping Exchange) { self.exchange = exchange }

    public var state: LifecycleState { lifecycle.state }

    public func invalidate() {
        generation += 1
        operation?.cancel()
        operation = nil
        lifecycle.loseIPC()
    }

    public func reconcile() async {
        guard operation == nil else { return }
        await perform(DaemonRequest(command: "hello"), handshake: true)
    }

    public func connect(_ profile: DaemonProfile) async {
        guard operation == nil, let request = lifecycle.connect(profile) else { return }
        await perform(request)
    }

    public func disconnect() async {
        guard operation == nil, let request = lifecycle.disconnect() else { return }
        await perform(request)
    }

    private func perform(_ request: DaemonRequest, handshake: Bool = false) async {
        let epoch = generation
        let exchange = exchange
        let task = Task { try await exchange(request) }
        operation = task
        do {
            let response = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard epoch == generation else { return }
            try Task.checkCancellation()
            operation = nil
            if let next = lifecycle.observe(response, handshake: handshake) {
                await perform(next)
            }
        } catch {
            guard epoch == generation else { return }
            operation = nil
            lifecycle.loseIPC()
        }
    }
}
