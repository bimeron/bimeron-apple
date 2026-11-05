import Foundation

/// Serializes user intent and discards responses from invalidated exchanges.
public actor DaemonClient {
    /// Must enforce an I/O deadline and responseLimit while receiving, before buffering untrusted input.
    public typealias FramedExchange = @Sendable (DaemonRequest) async throws -> Data
    public typealias Exchange = @Sendable (DaemonRequest) async throws -> DaemonResponse
    private let expectedRevision: String?
    private let exchange: Exchange
    private var lifecycle = DaemonLifecycle()
    private var generation = 0
    private var operation: Task<DaemonResponse, Error>?

    public init(expectedRevision: String? = nil) {
        self.expectedRevision = expectedRevision
        exchange = { try await DaemonSocketTransport().exchange($0) }
    }

    /// Injection is for deterministic local adapters; it does not authenticate a daemon.
    public init(exchange: @escaping Exchange, expectedRevision: String? = nil) { self.exchange = exchange; self.expectedRevision = expectedRevision }

    /// Reuses strict framing, duplicate-key rejection, size limits and request correlation.
    public init(framedExchange: @escaping FramedExchange) {
        expectedRevision = nil
        exchange = { request in
            try DaemonProtocol.decode(await framedExchange(request), request: request)
        }
    }

    public var actionError: String? { lifecycle.actionError }
    public var state: LifecycleState { lifecycle.state }
    public var session: DaemonSession? { lifecycle.session }
    public var guardsSupported: Bool { lifecycle.guardsSupported }

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
            if handshake, let expectedRevision,
               response.core?.revision != expectedRevision || response.core?.modified != false || response.core?.platform != "darwin" {
                lifecycle.loseIPC()
                return
            }
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
