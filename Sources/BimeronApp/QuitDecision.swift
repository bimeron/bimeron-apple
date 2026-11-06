/// Quit policy is independent of AppKit; Stop must include observed cleanup.
enum QuitDecision {
    enum Choice { case disconnect, keepRunning, cancel }
    enum Outcome: Equatable { case terminate, stayOpen, error(String) }

    static func needsConfirmation(reachable: Bool, active: Bool) -> Bool {
        reachable && active
    }

    @MainActor static func resolve(_ choice: Choice, stop: () async -> String?) async -> Outcome {
        switch choice {
        case .keepRunning: return .terminate
        case .cancel: return .stayOpen
        case .disconnect:
            if let error = await stop() { return .error(error) }
            return .terminate
        }
    }
}
