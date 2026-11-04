import Foundation

struct DiagnosticSnapshot: Identifiable {
    let id = UUID()
    let entries: [LogEntry]
    let profileCount: Int
    let capturedAt: Date
    let appVersion: String
    let osVersion: String
    private let timeZone: TimeZone

    init(entries: [LogEntry], profileCount: Int) {
        self.entries = entries
        self.profileCount = profileCount
        capturedAt = .now
        timeZone = .current
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        appVersion = !version.isEmpty && version.count <= 32 && version.allSatisfy { "0123456789.".contains($0) }
            ? version : "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    func text(includeFreeText: Bool) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        let records = entries.compactMap { entry -> String? in
            let timestamp = formatter.string(from: entry.date)
            if let event = entry.event {
                return "\(timestamp) source=\(event.source.rawValue) type=\(event.kind.rawValue) outcome=\(event.outcome.rawValue)"
                    + (event.attemptID.map { " guiAttempt=\($0.uuidString)" } ?? "")
            }
            return includeFreeText ? "\(timestamp) FREE TEXT: \(entry.message)" : nil
        }
        let latestLifecycle = entries.last { $0.event?.source == .lifecycle }?.event?.outcome ?? .unknown
        return (["Bimeron diagnostics", "Captured: \(formatter.string(from: capturedAt))",
                 "App: \(appVersion)", "macOS: \(osVersion)", "Profiles: \(profileCount)",
                 "Latest retained lifecycle observation: \(latestLifecycle.rawValue)",
                 "Free text: \(includeFreeText ? "included" : "excluded")", ""] + records).joined(separator: "\n")
    }
}
