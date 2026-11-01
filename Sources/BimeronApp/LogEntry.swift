import Foundation

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date.now
    let message: String
}
