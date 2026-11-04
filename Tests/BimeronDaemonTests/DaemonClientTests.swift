import Foundation
import XCTest
@testable import BimeronDaemon

private actor ControlledDaemon {
    private var pending: CheckedContinuation<DaemonResponse, Error>?
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private(set) var commands: [String] = []

    func exchange(_ request: DaemonRequest) async throws -> DaemonResponse {
        commands.append(request.command)
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            arrivals.forEach { $0.resume() }
            arrivals.removeAll()
        }
    }

    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { arrivals.append($0) }
    }

    func complete(state: String = "disconnected", instance: String = "one", guards: Bool = true) throws {
        let json = "{\"version\":1,\"id\":\"test\",\"instance\":\"\(instance)\",\"daemon_session_guards\":\(guards),\"status\":{\"State\":\"\(state)\"}}"
        let response = try JSONDecoder().decode(DaemonResponse.self, from: Data(json.utf8))
        let continuation = pending
        pending = nil
        continuation?.resume(returning: response)
    }

    func timeout() {
        let continuation = pending
        pending = nil
        continuation?.resume(throwing: DaemonError.timeout)
    }
}

final class DaemonClientTests: XCTestCase {
    func testTimeoutCoalescesClicksAndRequiresExplicitReconciliation() async throws {
        let daemon = ControlledDaemon()
        let client = DaemonClient(exchange: { try await daemon.exchange($0) })
        let hello = Task { await client.reconcile() }
        await daemon.waitForRequest()
        try await daemon.complete()
        await hello.value
        let profile = DaemonProfile(id: "A", configPath: "/A")
        let start = Task { await client.connect(profile) }
        await daemon.waitForRequest()
        await client.connect(profile)
        await client.disconnect()
        var commands = await daemon.commands
        XCTAssertEqual(commands, ["hello", "start"])
        await daemon.timeout()
        await start.value
        let state = await client.state
        XCTAssertEqual(state, .unknown)
        await client.connect(profile)
        commands = await daemon.commands
        XCTAssertEqual(commands, ["hello", "start"])
    }

    func testInvalidationDiscardsLateSuccessfulResponse() async throws {
        let daemon = ControlledDaemon()
        let client = DaemonClient(exchange: { try await daemon.exchange($0) })
        let hello = Task { await client.reconcile() }
        await daemon.waitForRequest()
        await client.invalidate()
        try await daemon.complete()
        await hello.value
        let state = await client.state
        XCTAssertEqual(state, .unknown)
        await client.connect(DaemonProfile(id: "A", configPath: "/A"))
        let commands = await daemon.commands
        XCTAssertEqual(commands, ["hello"])
    }

    func testCancellationDoesNotBecomeStopped() async throws {
        let daemon = ControlledDaemon()
        let client = DaemonClient(exchange: { try await daemon.exchange($0) })
        let hello = Task { await client.reconcile() }
        await daemon.waitForRequest()
        hello.cancel()
        try await daemon.complete()
        await hello.value
        let state = await client.state
        XCTAssertEqual(state, .unknown)
    }
}
