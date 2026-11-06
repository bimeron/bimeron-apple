import BimeronDaemon
import Foundation
import Testing
@testable import BimeronApp

@Test @MainActor func historicalCoreBatchDisplaysItsOwnTimesInCursorOrder() async throws {
    let times = ["2026-11-06T02:47:25+03:00", "2026-11-06T02:47:26.123456789+03:00",
                 "2026-11-05T23:47:24Z"]
    let connection = CoreConnection(client: DaemonClient(exchange: { request in
        let events: [[String: Any]] = times.enumerated().map { offset, time in
            ["sequence": offset + 1, "event": ["Time": time, "State": "connected", "Message": "event-\(offset)"]]
        }
        let body: [String: Any] = ["version": 1, "id": request.id, "instance": "instance",
            "daemon_session_guards": true, "status": ["State": "disconnected"], "events": events, "cursor": 3]
        return try DaemonProtocol.decode(JSONSerialization.data(withJSONObject: body) + Data([10]), request: request)
    }))
    await connection.refresh()
    let core = connection.journal
    #expect(core.map(\.message) == ["[connected] event-0", "[connected] event-1", "[connected] event-2"])
    let zone = try #require(TimeZone(secondsFromGMT: 3 * 3600))
    let displayed = core.map { $0.displayedTime(locale: Locale(identifier: "en_GB"), timeZone: zone) }
    #expect(displayed == ["2:47:25", "2:47:26", "2:47:24"])
    #expect(Set(displayed).count == 3)
    let local = LogEntry(message: "local", date: core[0].date.addingTimeInterval(0.5))
    let merged = LogEntry.merging(core: core, local: [local])
    #expect(merged.filter { $0.message != "local" } == core)
    // Core clocks can move backwards; the cursor must still determine their order.
    #expect(LogEntry.merging(core: Array(core.reversed()), local: [local]).filter { $0.message != "local" } == Array(core.reversed()))
}

@Test func missingOrUnusableCoreTimeFallsBackToReceiveTime() throws {
    let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)
    for value in [nil, "", "not-a-time"] as [String?] {
        var body = ["State": "connected", "Message": "event"]
        if let value { body["Time"] = value }
        let event = try JSONDecoder().decode(DaemonLoggedEvent.Event.self,
            from: JSONSerialization.data(withJSONObject: body))
        #expect(LogEntry(coreEvent: event, receivedAt: receivedAt).date == receivedAt)
    }
}
