import BimeronStatistics
import Foundation

/// A read-only projection; the caller owns identity confirmation and clock advancement.
struct StatisticsPresentation {
    let totals: ConnectionStatistics.Counters?
    let rate: ConnectionStatistics.Rate?
    let history: [ConnectionStatistics.Sample]

    init(snapshot: ConnectionStatistics?) {
        history = snapshot?.history ?? []
        guard let snapshot, snapshot.token != nil, !snapshot.needsResync,
              let latest = snapshot.latest else {
            totals = nil
            rate = nil
            return
        }
        totals = latest.counters
        rate = snapshot.status == .connected ? latest.rate : nil
    }

    static func bytes(_ value: Int64, locale: Locale) -> String {
        value.formatted(.byteCount(style: .file).locale(locale))
    }

    static func number(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    static func elapsed(_ duration: Duration, locale: Locale) -> String {
        let parts = duration.components
        return number(Double(parts.seconds) + Double(parts.attoseconds) / 1e18, locale: locale)
    }
}
