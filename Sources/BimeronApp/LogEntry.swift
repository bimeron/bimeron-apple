import Foundation

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let date = Date.now
    let message: String
    let event: DiagnosticEvent?

    init(message: String, event: DiagnosticEvent? = nil) {
        self.message = message
        self.event = event
    }
}
