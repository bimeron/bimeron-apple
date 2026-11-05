import Foundation
import XCTest
@testable import BimeronDaemon

private actor InterleavingDaemon {
    private var pending: [Int: CheckedContinuation<DaemonResponse, Error>] = [:]
    private var arrivals: [Int: [CheckedContinuation<DaemonRequest, Error>]] = [:]
    private enum Failure: Error { case deadlineExceeded, testFinished }
    private var failure: Failure?
    private var watchdog: Task<Void, Never>?
    private var deadlineID: UUID?
    private(set) var requests: [DaemonRequest] = []

    // The deadline only bounds failures; request arrivals determine normal ordering.
    private func armWatchdog() {
        guard watchdog == nil else { return }
        let id = UUID()
        deadlineID = id
        watchdog = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
            await self?.expire(id)
        }
    }

    private func stopWatchdogIfIdle() {
        guard pending.isEmpty, arrivals.isEmpty else { return }
        watchdog?.cancel()
        watchdog = nil
        deadlineID = nil
    }

    private func expire(_ id: UUID) {
        guard deadlineID == id, failure == nil else { return }
        XCTFail("Fake daemon deadline exceeded; pending exchanges: \(pending.keys.sorted()), awaited arrivals: \(arrivals.keys.sorted())")
        terminate(with: .deadlineExceeded)
    }

    private func terminate(with error: Failure) {
        failure = error
        watchdog?.cancel()
        watchdog = nil
        deadlineID = nil
        let exchanges = pending.values
        let waiters = arrivals.values.flatMap { $0 }
        pending.removeAll()
        arrivals.removeAll()
        for continuation in exchanges { continuation.resume(throwing: error) }
        for continuation in waiters { continuation.resume(throwing: error) }
    }

    func finish() {
        terminate(with: .testFinished)
    }

    func exchange(_ request: DaemonRequest) async throws -> DaemonResponse {
        if let failure { throw failure }
        armWatchdog()
        let index = requests.count
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuation in
            pending[index] = continuation
            for waiter in arrivals.removeValue(forKey: index) ?? [] {
                waiter.resume(returning: request)
            }
        }
    }

    func request(at index: Int) async throws -> DaemonRequest {
        if let failure { throw failure }
        if requests.indices.contains(index) { return requests[index] }
        armWatchdog()
        return try await withCheckedThrowingContinuation { arrivals[index, default: []].append($0) }
    }

    func succeed(_ index: Int, state: String = "disconnected", active: Bool = false,
                 profile: String = "A") throws {
        if let failure { throw failure }
        let object: [String: Any] = [
            "version": 1, "id": requests[index].id, "instance": "one",
            "daemon_session_guards": true,
            "status": ["State": state,
                       "Session": ["id": "session", "active": active, "profile_id": profile]]
        ]
        let response = try JSONDecoder().decode(
            DaemonResponse.self, from: JSONSerialization.data(withJSONObject: object))
        pending.removeValue(forKey: index)!.resume(returning: response)
        stopWatchdogIfIdle()
    }

    func fail(_ index: Int, with error: DaemonError) throws {
        if let failure { throw failure }
        pending.removeValue(forKey: index)!.resume(throwing: error)
        stopWatchdogIfIdle()
    }
}

final class DaemonClientInterleavingTests: XCTestCase {
    private let a = DaemonProfile(id: "A", configPath: "/A")
    private let b = DaemonProfile(id: "B", configPath: "/B")

    private func makeDaemon() -> InterleavingDaemon {
        let daemon = InterleavingDaemon()
        addTeardownBlock { await daemon.finish() }
        return daemon
    }

    private func reconcile(_ client: DaemonClient, daemon: InterleavingDaemon,
                           at index: Int, state: String = "disconnected", active: Bool = false) async throws {
        let task = Task { await client.reconcile() }
        let request = try await daemon.request(at: index)
        XCTAssertEqual(request.command, "hello")
        try await daemon.succeed(index, state: state, active: active)
        await task.value
    }

    private func assertState(_ expected: LifecycleState, of client: DaemonClient,
                             file: StaticString = #filePath, line: UInt = #line) async {
        let state = await client.state
        XCTAssertEqual(state, expected, file: file, line: line)
    }

    private func assertCommands(_ expected: [String], from daemon: InterleavingDaemon,
                                file: StaticString = #filePath, line: UInt = #line) async {
        let commands = await daemon.requests.map(\.command)
        XCTAssertEqual(commands, expected, file: file, line: line)
    }

    func testDelayedSuccessfulStartSuppressesAllRepeatedIntents() async throws {
        let daemon = makeDaemon()
        let client = DaemonClient(exchange: { try await daemon.exchange($0) })
        try await reconcile(client, daemon: daemon, at: 0)
        let start = Task { [a] in await client.connect(a) }
        let request = try await daemon.request(at: 1)
        XCTAssertEqual(request.command, "start")
        XCTAssertEqual(request.config, "/A")
        await assertState(.starting, of: client)
        for _ in 0..<2 {
            await client.reconcile()
            await client.connect(a)
            await client.connect(b)
            await client.disconnect()
        }
        await assertCommands(["hello", "start"], from: daemon)
        try await daemon.succeed(1, state: "connected", active: true)
        await start.value
        await assertState(.connected, of: client)
        await client.connect(a)
        await assertCommands(["hello", "start"], from: daemon)
    }

    func testSwitchStartsReplacementOnlyAfterInactiveConfirmation() async throws {
        let daemon = makeDaemon()
        let client = DaemonClient(exchange: { try await daemon.exchange($0) })
        try await reconcile(client, daemon: daemon, at: 0, state: "connected", active: true)
        let switchProfile = Task { [b] in await client.connect(b) }
        let stop = try await daemon.request(at: 1)
        XCTAssertEqual(stop.command, "stop")
        XCTAssertEqual(stop.session, "session")
        await client.reconcile()
        await client.connect(a)
        await client.disconnect()
        await assertCommands(["hello", "stop"], from: daemon)
        try await daemon.succeed(1, active: true)
        await switchProfile.value
        await assertCommands(["hello", "stop"], from: daemon)
        await client.connect(b)
        await assertCommands(["hello", "stop"], from: daemon)

        let confirmation = Task { await client.reconcile() }
        let hello = try await daemon.request(at: 2)
        XCTAssertEqual(hello.command, "hello")
        try await daemon.succeed(2)
        let replacement = try await daemon.request(at: 3)
        XCTAssertEqual(replacement.command, "start")
        XCTAssertEqual(replacement.config, "/B")
        await assertState(.starting, of: client)
        await client.reconcile()
        await client.disconnect()
        await assertCommands(["hello", "stop", "hello", "start"], from: daemon)
        try await daemon.succeed(3, state: "connected", active: true, profile: "B")
        await confirmation.value
        await assertState(.connected, of: client)
    }

    func testDisconnectErrorsRequireExplicitReconciliationWithoutRetry() async throws {
        for error in [DaemonError.timeout, .unavailable] {
            let daemon = makeDaemon()
            let client = DaemonClient(exchange: { try await daemon.exchange($0) })
            try await reconcile(client, daemon: daemon, at: 0, state: "connected", active: true)
            let disconnect = Task { await client.disconnect() }
            let stop = try await daemon.request(at: 1)
            XCTAssertEqual(stop.command, "stop")
            try await daemon.fail(1, with: error)
            await disconnect.value
            await assertState(.unknown, of: client)
            await client.disconnect()
            await client.connect(a)
            await client.connect(b)
            await assertCommands(["hello", "stop"], from: daemon)
            try await reconcile(client, daemon: daemon, at: 2)
            await assertState(.stopped, of: client)
            await assertCommands(["hello", "stop", "hello"], from: daemon)
        }
    }

    func testStaleSuccessAndFailureCannotMutateOrReleaseNewerOperation() async throws {
        for staleSucceeds in [true, false] {
            let daemon = makeDaemon()
            let client = DaemonClient(exchange: { try await daemon.exchange($0) })
            let stale = Task { await client.reconcile() }
            let oldHello = try await daemon.request(at: 0)
            XCTAssertEqual(oldHello.command, "hello")
            await client.invalidate()
            try await reconcile(client, daemon: daemon, at: 1)
            let start = Task { [b] in await client.connect(b) }
            let newer = try await daemon.request(at: 2)
            XCTAssertEqual(newer.command, "start")
            if staleSucceeds {
                try await daemon.succeed(0, state: "connected", active: true)
            } else {
                try await daemon.fail(0, with: .unavailable)
            }
            await stale.value
            await assertState(.starting, of: client)
            await client.reconcile()
            await client.connect(a)
            await client.disconnect()
            await assertCommands(["hello", "hello", "start"], from: daemon)
            try await daemon.succeed(2, state: "connected", active: true, profile: "B")
            await start.value
            await assertState(.connected, of: client)
            await client.connect(b)
            await assertCommands(["hello", "hello", "start"], from: daemon)
        }
    }
}
