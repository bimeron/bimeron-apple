import Foundation

struct DiagnosticHistory {
    static let entryLimit = 5_000
    static let textLimit = 4 * 1_024 * 1_024
    private(set) var entries: [LogEntry] = []
    private(set) var textBytes = 0

    mutating func append(_ message: String, event: DiagnosticEvent? = nil) {
        var bytes = Array(message.utf8.prefix(Self.textLimit))
        // A UTF-8 prefix can end inside a scalar; discard only that incomplete scalar.
        while String(bytes: bytes, encoding: .utf8) == nil { bytes.removeLast() }
        let text = String(decoding: bytes, as: UTF8.self)
        entries.append(LogEntry(message: text, event: event))
        textBytes += bytes.count
        while entries.count > Self.entryLimit || textBytes > Self.textLimit {
            textBytes -= entries.removeFirst().message.utf8.count
        }
    }

    mutating func clear() {
        entries.removeAll()
        textBytes = 0
    }
}
