import Foundation

public enum LifecycleState: Equatable, Sendable {
    case unknown, stopped, connected, starting, stopping, cleanupUnconfirmed
}

public struct DaemonProfile: Equatable, Sendable {
    public let id: String
    public let configPath: String
    public init(id: String, configPath: String) { self.id = id; self.configPath = configPath }
}

/// A deterministic reducer. The caller executes returned requests and feeds authoritative responses back.
public struct DaemonLifecycle: Sendable {
    public private(set) var state: LifecycleState = .unknown
    public private(set) var instance: String?
    public private(set) var session: DaemonSession?
    public private(set) var guardsSupported = false
    private var replacement: DaemonProfile?
    private var pending = false

    public init() {}

    public mutating func loseIPC() {
        state = .unknown
        replacement = nil
        pending = false
        guardsSupported = false
    }

    public mutating func observe(_ response: DaemonResponse, handshake: Bool = false) -> DaemonRequest? {
        let restarted = instance != nil && instance != response.instance
        if restarted { loseIPC() }
        instance = response.instance
        if handshake { guardsSupported = response.daemon_session_guards == true }
        session = response.status.Session
        if response.error != nil {
            replacement = nil
            pending = false
            state = .cleanupUnconfirmed
            return nil
        }
        if response.status.cleanupConfirmed {
            state = .stopped
            pending = false
            if !restarted, let next = replacement {
                replacement = nil
                return connect(next)
            }
        } else if response.status.State == "connected", session?.active == true {
            if !pending { state = .connected }
            else if state == .starting { pending = false; state = .connected }
        } else if !pending { state = .unknown }
        return nil
    }

    public mutating func connect(_ profile: DaemonProfile) -> DaemonRequest? {
        guard !pending, guardsSupported, let instance else { return nil }
        if state == .connected {
            guard session?.profile_id != profile.id else { return nil }
            replacement = profile
            return disconnect()
        }
        guard state == .stopped, profile.configPath.hasPrefix("/") else { return nil }
        pending = true
        state = .starting
        return DaemonRequest(command: "start", instance: instance, config: profile.configPath)
    }

    public mutating func disconnect() -> DaemonRequest? {
        guard !pending, guardsSupported, state == .connected,
              let instance, let session, session.active, !session.id.isEmpty else { return nil }
        pending = true
        state = .stopping
        return DaemonRequest(command: "stop", instance: instance, session: session.id)
    }
}
