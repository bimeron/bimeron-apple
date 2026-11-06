import Foundation
import BimeronDaemon

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let message: String
    let event: DiagnosticEvent?

    init(message: String, event: DiagnosticEvent? = nil, date: Date = .now) {
        self.date = date
        self.message = message
        self.event = event
    }

    init(coreEvent: DaemonLoggedEvent.Event, receivedAt: Date) {
        let timestamp = coreEvent.Time.flatMap {
            (try? Date($0, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
                ?? (try? Date($0, strategy: .iso8601))
        }
        self.init(message: coreEvent.line, date: timestamp ?? receivedAt)
    }

    func displayedTime(locale: Locale, timeZone: TimeZone = .current) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .standard, locale: locale, timeZone: timeZone))
    }

    /// Interleave local diagnostics without changing Core cursor order, even after clock adjustments.
    static func merging(core: [LogEntry], local: [LogEntry]) -> [LogEntry] {
        var pending = ArraySlice(local.sorted { $0.date < $1.date })
        var result: [LogEntry] = []
        for entry in core {
            while let first = pending.first, first.date <= entry.date {
                result.append(pending.removeFirst())
            }
            result.append(entry)
        }
        result.append(contentsOf: pending)
        return result
    }
}
