import XCTest
@testable import BimeronStatistics

/// All observations and elapsed clock values in this suite are synthetic.
final class ConnectionStatisticsTests: XCTestCase {
    typealias Model = ConnectionStatistics
    let identity = Model.Identity(instance: "synthetic-daemon", session: "synthetic-session")
    func model() -> Model { Model(staleAfter: .seconds(3), historyLimit: 2, eventLimit: 2) }
    @discardableResult
    func feed(_ model: inout Model, _ token: Model.Token, _ sequence: UInt64, _ time: Duration,
              _ up: Int64?, _ down: Int64 = 0, status: Model.Status = .connected) -> Bool {
        model.observe(token: token, sequence: sequence, at: time, status: status,
                      counters: up.map { .init(bytesUp: $0, bytesDown: down) })
    }
    func testSavedSyntheticContractFixture() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/synthetic-byte-observations.json")
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let provenance = try XCTUnwrap(fixture["provenance"] as? [String: String])
        XCTAssertEqual(provenance["core_revision"], "c04f20d575e4aed979b1024a32b421e7e5de1afe")
        XCTAssertTrue(try XCTUnwrap(provenance["kind"]).contains("not actual Core samples"))
        let samples = try XCTUnwrap(fixture["samples"] as? [[String: Any]])
        XCTAssertEqual(samples.count, 5)
        var model = model(); let token = model.confirm(identity)
        for (index, sample) in samples.enumerated() {
            let time = try XCTUnwrap(sample["elapsed_milliseconds"] as? Int64)
            let unavailable = try XCTUnwrap(sample["unavailable"] as? Bool)
            let up = try XCTUnwrap(sample["bytes_up"] as? Int64)
            let down = try XCTUnwrap(sample["bytes_down"] as? Int64)
            XCTAssertTrue(feed(&model, token, UInt64(index + 1), .milliseconds(time),
                               unavailable ? nil : up, down))
            switch index {
            case 0, 3:
                XCTAssertEqual(model.latest?.counters?.bytesUp, 0)
                XCTAssertNil(model.latest?.rate)
            case 1:
                XCTAssertEqual(model.latest?.rate?.bytesUpPerSecond, 40)
                XCTAssertEqual(model.latest?.rate?.bytesDownPerSecond, 80)
            case 2:
                XCTAssertNil(model.latest?.counters)
                XCTAssertNil(model.latest?.rate)
            case 4:
                XCTAssertEqual(model.latest?.rate?.bytesUpPerSecond, 0)
                XCTAssertEqual(model.latest?.rate?.bytesDownPerSecond, 0)
            default: XCTFail("Unexpected synthetic sample")
            }
        }
    }
    func testFractionalRatesAndFreshZero() {
        var model = model(); let token = model.confirm(identity)
        feed(&model, token, 1, .zero, 0)
        XCTAssertEqual(model.latest?.counters?.bytesUp, 0)
        XCTAssertNil(model.latest?.rate)
        feed(&model, token, 2, .milliseconds(250), 10, 20)
        XCTAssertEqual(model.latest?.rate?.bytesUpPerSecond, 40)
        XCTAssertEqual(model.latest?.rate?.bytesDownPerSecond, 80)
        feed(&model, token, 3, .milliseconds(750), 10, 20)
        XCTAssertEqual(model.latest?.rate?.bytesUpPerSecond, 0)
        XCTAssertEqual(model.history.count, 2)
    }
    func testResetDecreaseOverflowAndUnavailableBreakRates() {
        for invalid: Int64? in [5, -1, Int64.min, nil] {
            var model = model(); let token = model.confirm(identity)
            feed(&model, token, 1, .zero, Int64.max)
            feed(&model, token, 2, .seconds(1), invalid)
            XCTAssertNil(model.latest?.rate)
            if invalid == nil || invalid! < 0 { XCTAssertNil(model.latest?.counters) }
            feed(&model, token, 3, .seconds(2), 6)
            if invalid == 5 { XCTAssertEqual(model.latest?.rate?.bytesUpPerSecond, 1) }
            else { XCTAssertNil(model.latest?.rate) }
        }
        var model = model(); let token = model.confirm(identity)
        feed(&model, token, 1, .zero, 0, 100)
        feed(&model, token, 2, .seconds(1), 10, 99)
        XCTAssertNil(model.latest?.rate)
    }
    func testReconnectAndConfirmationInvalidateBaselineAndOldWork() {
        var model = model(); var token = model.confirm(identity)
        feed(&model, token, 1, .zero, 10)
        feed(&model, token, 2, .seconds(1), 20, status: .reconnecting)
        feed(&model, token, 3, .seconds(2), 30)
        XCTAssertNil(model.latest?.rate)
        for next in [identity, .init(instance: identity.instance, session: "new-session"),
                     .init(instance: "new-daemon", session: "new-session")] {
            let old = token; token = model.confirm(next)
            XCTAssertFalse(feed(&model, old, 99, .seconds(3), 100))
            feed(&model, token, 1, .seconds(3), 40)
            XCTAssertNil(model.latest?.rate)
        }
        model.loseIPC()
        XCTAssertEqual(model.status, .unknown)
        XCTAssertNil(model.latest)
        XCTAssertFalse(feed(&model, token, 100, .seconds(4), 50))
        token = model.confirm(identity)
        feed(&model, token, 1, .seconds(4), 50)
        XCTAssertNil(model.latest?.rate)
    }
    func testStalenessAndOutOfOrderUpdates() {
        var model = model(); let token = model.confirm(identity)
        feed(&model, token, 2, .seconds(1), 10)
        XCTAssertFalse(feed(&model, token, 1, .seconds(2), 20))
        XCTAssertFalse(feed(&model, token, 3, .zero, 20))
        XCTAssertFalse(feed(&model, token, 3, .seconds(1), 20))
        XCTAssertTrue(model.advance(to: .seconds(4)))
        XCTAssertNil(model.latest)
        XCTAssertFalse(model.advance(to: .seconds(3)))
        feed(&model, token, 3, .seconds(4), 30)
        XCTAssertNil(model.latest?.rate)
        feed(&model, token, 4, .seconds(7), 40)
        XCTAssertNil(model.latest?.rate)
    }
    func testEventsAreBoundedOrderedAndNeverEstablishStatus() {
        var model = model(); let token = model.confirm(identity)
        XCTAssertTrue(model.observeEvents(token: token, cursor: 3, dropped: false,
            events: (1...3).map { .init(sequence: UInt64($0), code: "synthetic-connected") }))
        XCTAssertEqual(model.events.map(\.sequence), [2, 3])
        XCTAssertEqual(model.status, .unknown)
        XCTAssertFalse(model.observeEvents(token: token, cursor: 4, dropped: false,
                                           events: [.init(sequence: 3, code: "synthetic-duplicate")]))
        XCTAssertFalse(model.observeEvents(token: token, cursor: 2, dropped: false, events: []))
        XCTAssertFalse(model.observeEvents(token: token, cursor: 5, dropped: false,
                                           events: [.init(sequence: 5, code: "later"), .init(sequence: 4, code: "earlier")]))
        XCTAssertFalse(model.observeEvents(token: token, cursor: 4, dropped: false,
                                           events: [.init(sequence: 5, code: "beyond-cursor")]))
        XCTAssertEqual(model.cursor, 3)
        XCTAssertEqual(model.events.map(\.sequence), [2, 3])
        XCTAssertTrue(model.observeEvents(token: token, cursor: 5, dropped: true, events: []))
        XCTAssertTrue(model.needsResync)
        XCTAssertNil(model.token)
        XCTAssertFalse(feed(&model, token, 1, .zero, 0))
    }
    func testDisconnectedTotalsAreRetainedWithoutRateAndZeroBounds() {
        var model = Model(staleAfter: .seconds(1), historyLimit: 0, eventLimit: 0)
        let token = model.confirm(identity)
        feed(&model, token, 1, .zero, 100, status: .disconnected)
        XCTAssertEqual(model.latest?.counters?.bytesUp, 100)
        XCTAssertNil(model.latest?.rate)
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertTrue(model.observeEvents(token: token, cursor: 1, dropped: false,
                                          events: [.init(sequence: 1, code: "synthetic")]))
        XCTAssertTrue(model.events.isEmpty)
    }
}
