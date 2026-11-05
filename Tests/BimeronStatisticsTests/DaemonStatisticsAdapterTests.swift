import Foundation
import XCTest
import BimeronDaemon
@testable import BimeronStatistics

private final class SyntheticClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Duration = .zero
    func now() -> Duration { lock.withLock { time } }
    func set(_ value: Duration) { lock.withLock { time = value } }
}

/// Synthetic wire responses, shaped from Core 0d5fd06's CONTROL.MD and ADR 0033.
private actor SnapshotTransport {
    var supported = true
    var instance = "daemon"
    var session = "session"
    var state = "connected"
    var attempt = 1
    var counters = #"{"bytes_up":0,"bytes_down":0}"#
    var error: String?
    var wrongID = false
    var omitSession = false
    var omitSnapshot = false
    var commands: [String] = []
    var held = false
    private var pending: CheckedContinuation<Void, Never>?
    private var arrived: CheckedContinuation<Void, Never>?

    func configure(instance: String = "daemon", session: String = "session", state: String = "connected",
                   attempt: Int = 1, counters: String = #"{"bytes_up":0,"bytes_down":0}"#,
                   supported: Bool = true, error: String? = nil, wrongID: Bool = false,
                   omitSession: Bool = false, omitSnapshot: Bool = false, held: Bool = false) {
        self.instance = instance; self.session = session; self.state = state; self.attempt = attempt
        self.counters = counters; self.supported = supported; self.error = error
        self.wrongID = wrongID; self.omitSession = omitSession; self.omitSnapshot = omitSnapshot; self.held = held
    }

    func exchange(_ request: DaemonRequest) async -> Data {
        commands.append(request.command)
        if held {
            await withCheckedContinuation { continuation in
                pending = continuation
                arrived?.resume(); arrived = nil
            }
        }
        var fields: [String: Any] = ["version": 1, "id": wrongID ? "foreign" : request.id,
                                     "instance": instance, "status": ["State": "failed"]]
        if request.command == "hello" { fields["session_bound_stats"] = supported }
        else if !omitSnapshot {
            var inner: [String: Any] = ["State": state, "Attempt": attempt]
            if !omitSession { inner["Session"] = ["id": session, "active": state != "disconnected"] }
            fields["stats_snapshot"] = ["status": inner,
                "counters": try! JSONSerialization.jsonObject(with: Data(counters.utf8))]
        }
        if let error { fields["error"] = error }
        var data = try! JSONSerialization.data(withJSONObject: fields)
        data.append(10)
        return data
    }

    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { arrived = $0 }
    }
    func release() { held = false; pending?.resume(); pending = nil }
}

final class DaemonStatisticsAdapterTests: XCTestCase {
    private let identity = ConnectionStatistics.Identity(instance: "daemon", session: "session")
    private func adapter(_ wire: SnapshotTransport, _ clock: SyntheticClock) -> DaemonStatisticsAdapter {
        .init(statistics: .init(staleAfter: .seconds(3), historyLimit: 2, eventLimit: 0),
              transport: { await wire.exchange($0) }, elapsed: { clock.now() })
    }

    func testInnerIdentityAttemptContinuityRatesAndRetainedTerminalTotals() async {
        let wire = SnapshotTransport(); let clock = SyntheticClock(); let adapter = adapter(wire, clock)
        await adapter.confirm(identity)
        var accepted = await adapter.poll(); XCTAssertTrue(accepted)
        var model = await adapter.statistics
        XCTAssertEqual(model.status, .connected) // Outer status deliberately says failed.
        XCTAssertEqual(model.latest?.counters?.bytesUp, 0)
        clock.set(.milliseconds(250))
        await wire.configure(attempt: 2, counters: #"{"bytes_up":10,"bytes_down":20}"#)
        accepted = await adapter.poll(); XCTAssertTrue(accepted)
        model = await adapter.statistics
        XCTAssertEqual(model.latest?.rate?.bytesUpPerSecond, 40)
        XCTAssertEqual(model.latest?.rate?.bytesDownPerSecond, 80)
        clock.set(.seconds(1))
        await wire.configure(state: "disconnected", counters: #"{"bytes_up":10,"bytes_down":20}"#)
        accepted = await adapter.poll(); XCTAssertTrue(accepted)
        model = await adapter.statistics
        XCTAssertEqual(model.latest?.counters?.bytesUp, 10)
        XCTAssertNil(model.latest?.rate)
        XCTAssertEqual(model.history.count, 2)
    }

    func testUnsupportedNeverFallsBackOrInventsSession() async {
        let wire = SnapshotTransport(); let clock = SyntheticClock(); let adapter = adapter(wire, clock)
        var accepted = await adapter.poll(); XCTAssertFalse(accepted)
        var commands = await wire.commands; XCTAssertTrue(commands.isEmpty)
        await adapter.confirm(identity)
        await wire.configure(supported: false)
        accepted = await adapter.poll(); XCTAssertFalse(accepted)
        commands = await wire.commands; XCTAssertEqual(commands, ["hello"])
        let model = await adapter.statistics
        XCTAssertNil(model.token); XCTAssertNil(model.latest)
    }

    func testRejectsMismatchErrorsAbsentOwnershipAndInvalidByteNumbers() async {
        for scenario in 0..<10 {
            let wire = SnapshotTransport(); let clock = SyntheticClock(); let adapter = adapter(wire, clock)
            await adapter.confirm(identity)
            switch scenario {
            case 0: await wire.configure(instance: "replacement")
            case 1: await wire.configure(session: "replacement")
            case 2: await wire.configure(error: "unknown_command")
            case 3: await wire.configure(wrongID: true)
            case 4: await wire.configure(omitSession: true)
            case 5: await wire.configure(omitSnapshot: true)
            case 6: await wire.configure(counters: #"{"bytes_up":-1,"bytes_down":0}"#)
            case 7: await wire.configure(counters: #"{"bytes_up":9223372036854775808,"bytes_down":0}"#)
            case 8: await wire.configure(counters: #"{"bytes_up":1.5,"bytes_down":0}"#)
            default: await wire.configure(state: "future-state")
            }
            let accepted = await adapter.poll(); XCTAssertFalse(accepted, "scenario \(scenario)")
            let model = await adapter.statistics
            XCTAssertNil(model.latest); XCTAssertTrue(model.needsResync)
        }
    }

    func testUnavailableDecreaseAndMonotonicGapBreakBaseline() async {
        let wire = SnapshotTransport(); let clock = SyntheticClock(); let adapter = adapter(wire, clock)
        await adapter.confirm(identity)
        _ = await adapter.poll()
        for (index, counters) in [
            #"{"bytes_up":20,"bytes_down":30}"#,
            #"{"bytes_up":0,"bytes_down":0,"unavailable":true}"#,
            #"{"bytes_up":10,"bytes_down":10}"#,
            #"{"bytes_up":9,"bytes_down":11}"#
        ].enumerated() {
            clock.set(.milliseconds((index + 1) * 250))
            await wire.configure(counters: counters)
            let accepted = await adapter.poll(); XCTAssertTrue(accepted)
            let model = await adapter.statistics
            if index > 0 { XCTAssertNil(model.latest?.rate) }
            if index == 1 { XCTAssertNil(model.latest?.counters) }
        }
        clock.set(.seconds(4)); await adapter.advance()
        var model = await adapter.statistics; XCTAssertNil(model.latest)
        _ = await adapter.poll()
        model = await adapter.statistics; XCTAssertNil(model.latest?.rate)
        clock.set(.seconds(3))
        let accepted = await adapter.poll(); XCTAssertFalse(accepted)
    }

    func testSingleFlightAndLateReplyCannotReplaceNewConfirmation() async {
        let wire = SnapshotTransport(); let clock = SyntheticClock(); let adapter = adapter(wire, clock)
        await adapter.confirm(identity)
        await wire.configure(held: true)
        let poll = Task { await adapter.poll() }
        await wire.waitForRequest()
        let concurrent = await adapter.poll(); XCTAssertFalse(concurrent)
        await adapter.confirm(.init(instance: "daemon", session: "new-session"))
        await wire.release()
        let accepted = await poll.value; XCTAssertFalse(accepted)
        let model = await adapter.statistics
        XCTAssertEqual(model.token?.identity.session, "new-session")
        XCTAssertNil(model.latest)
    }

    func testOverdueReplyInvalidatesConfirmation() async {
        let wire = SnapshotTransport(); let clock = SyntheticClock(); let adapter = adapter(wire, clock)
        await adapter.confirm(identity)
        await wire.configure(held: true)
        let poll = Task { await adapter.poll() }
        await wire.waitForRequest()
        clock.set(.seconds(3))
        await wire.release()
        let accepted = await poll.value; XCTAssertFalse(accepted)
        let model = await adapter.statistics; XCTAssertNil(model.token); XCTAssertNil(model.latest)
    }
    func testCancelledPollCannotPublishEvenWhenTransportReturnsSuccessfully() async {
        let wire = SnapshotTransport(); let clock = SyntheticClock(); let adapter = adapter(wire, clock)
        await adapter.confirm(identity)
        await wire.configure(held: true)
        let poll = Task { await adapter.poll() }
        await wire.waitForRequest()
        poll.cancel()
        await wire.release()
        let accepted = await poll.value; XCTAssertFalse(accepted)
        let model = await adapter.statistics
        XCTAssertNil(model.latest); XCTAssertNil(model.token)
        let commands = await wire.commands
        XCTAssertEqual(commands, ["hello"])
    }

}
