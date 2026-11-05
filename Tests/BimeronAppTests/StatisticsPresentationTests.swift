import Foundation
import Testing
import BimeronStatistics
@testable import BimeronApp

struct StatisticsPresentationTests {
    @Test func missingAndUnconfirmedSnapshotsAreUnavailable() {
        let empty = StatisticsPresentation(snapshot: nil)
        #expect(empty.totals == nil)
        #expect(empty.rate == nil)
        #expect(empty.history.isEmpty)
        let unconfirmed = StatisticsPresentation(snapshot: makeStatistics())
        #expect(unconfirmed.totals == nil)
        #expect(unconfirmed.rate == nil)
    }

    @Test func freshZeroAndFractionalRatesRemainAvailable() {
        var statistics = makeStatistics()
        let token = statistics.confirm(.init(instance: "synthetic", session: "session"))
        statistics.observe(token: token, sequence: 1, at: .zero, status: .connected,
                           counters: .init(bytesUp: 0, bytesDown: 0))
        #expect(StatisticsPresentation(snapshot: statistics).totals?.bytesDown == 0)
        #expect(StatisticsPresentation(snapshot: statistics).rate == nil)
        statistics.observe(token: token, sequence: 2, at: .milliseconds(500), status: .connected,
                           counters: .init(bytesUp: 1, bytesDown: 2))
        let presentation = StatisticsPresentation(snapshot: statistics)
        #expect(presentation.rate?.bytesUpPerSecond == 2)
        #expect(presentation.rate?.bytesDownPerSecond == 4)
        #expect(StatisticsPresentation.elapsed(.milliseconds(1250), locale: Locale(identifier: "en_US")) == "1.25")
    }

    @Test func staleAndResyncKeepHistoryWithoutCurrentValues() {
        var statistics = makeStatistics()
        let token = statistics.confirm(.init(instance: "synthetic", session: "session"))
        statistics.observe(token: token, sequence: 1, at: .zero, status: .connected,
                           counters: .init(bytesUp: 10, bytesDown: 20))
        statistics.advance(to: .seconds(10))
        let stale = StatisticsPresentation(snapshot: statistics)
        #expect(stale.totals == nil)
        #expect(stale.rate == nil)
        #expect(stale.history.count == 1)
        statistics.observe(token: token, sequence: 2, at: .seconds(11), status: .connected,
                           counters: .init(bytesUp: 30, bytesDown: 40))
        statistics.observeEvents(token: token, cursor: 0, dropped: true, events: [])
        let resync = StatisticsPresentation(snapshot: statistics)
        #expect(resync.totals == nil)
        #expect(resync.rate == nil)
        #expect(resync.history.count == 2)
    }

    @Test func boundedHistoryPreservesGapsAndDisconnectedTotals() {
        var statistics = makeStatistics()
        let token = statistics.confirm(.init(instance: "synthetic", session: "session"))
        statistics.observe(token: token, sequence: 1, at: .zero, status: .connected,
                           counters: .init(bytesUp: 1, bytesDown: 2))
        statistics.observe(token: token, sequence: 2, at: .seconds(1), status: .connected, counters: nil)
        statistics.observe(token: token, sequence: 3, at: .seconds(2), status: .connected,
                           counters: .init(bytesUp: 3, bytesDown: 4))
        statistics.observe(token: token, sequence: 4, at: .seconds(3), status: .disconnected,
                           counters: .init(bytesUp: 5, bytesDown: 6))
        let presentation = StatisticsPresentation(snapshot: statistics)
        #expect(presentation.totals?.bytesDown == 6)
        #expect(presentation.rate == nil)
        #expect(presentation.history.map(\.elapsed) == [.seconds(1), .seconds(2), .seconds(3)])
        #expect(presentation.history.first?.counters == nil)
        #expect(presentation.history.allSatisfy { $0.rate == nil })
    }

    @Test func formattingUsesSelectedEnglishAndRussianLocales() {
        let english = Locale(identifier: "en")
        let russian = Locale(identifier: "ru")
        let englishBytes = StatisticsPresentation.bytes(1_500_000, locale: english)
        let russianBytes = StatisticsPresentation.bytes(1_500_000, locale: russian)
        #expect(englishBytes.contains("1.5"))
        #expect(englishBytes.contains("MB"))
        #expect(russianBytes.contains("1,5"))
        #expect(russianBytes.contains("МБ"))
        #expect(StatisticsPresentation.number(1.25, locale: english) == "1.25")
        #expect(StatisticsPresentation.number(1.25, locale: russian) == "1,25")
        #expect(StatisticsPresentation.elapsed(.milliseconds(1250), locale: russian) == "1,25")
    }

    @Test func compactTrafficShowsLiveTotalsWithoutInventingMissingSamples() {
        let locale = Locale(identifier: "en")
        #expect(StatisticsPresentation(snapshot: nil).compactTraffic(connected: false, locale: locale) == "↓ 0 B   ↑ 0 B")
        #expect(StatisticsPresentation(snapshot: nil).compactTraffic(connected: true, locale: locale) == "↓ —   ↑ —")
        var statistics = makeStatistics()
        let token = statistics.confirm(.init(instance: "synthetic", session: "session"))
        statistics.observe(token: token, sequence: 1, at: .zero, status: .connected,
                           counters: .init(bytesUp: 0, bytesDown: 0))
        #expect(StatisticsPresentation(snapshot: statistics).compactTraffic(connected: true, locale: locale) == "↓ 0 B   ↑ 0 B")
        statistics.observe(token: token, sequence: 2, at: .seconds(1), status: .connected,
                           counters: .init(bytesUp: 1000, bytesDown: 2000))
        let line = StatisticsPresentation(snapshot: statistics).compactTraffic(connected: true, locale: locale)
        #expect(line == "↓ " + StatisticsPresentation.bytes(2000, locale: locale) + "   ↑ " + StatisticsPresentation.bytes(1000, locale: locale))
        statistics.loseIPC()
        #expect(StatisticsPresentation(snapshot: statistics).compactTraffic(connected: true, locale: locale) == "↓ —   ↑ —")
    }

    private func makeStatistics() -> ConnectionStatistics {
        ConnectionStatistics(staleAfter: .seconds(10), historyLimit: 3, eventLimit: 0)
    }
}
