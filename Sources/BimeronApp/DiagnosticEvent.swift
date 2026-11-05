import Foundation

struct DiagnosticEvent: Equatable {
    enum Source: String { case gui, coreCLI, lifecycle }
    enum Kind: String { case profileSave, profileCreate, profileAdd, profileImport, validation, observation, ipc }
    enum Outcome: String {
        case started, success, unavailable, cancelled, timedOut, rejected, failed
        case unknown, stopped, connecting, connected, reconnecting, starting, stopping, cleanupUnconfirmed
    }
    let source: Source
    let kind: Kind
    let outcome: Outcome
    let attemptID: UUID?
}
