import Foundation

public enum LifecycleState: Equatable, Sendable {
    case unknown, stopped, connecting, connected, reconnecting, failed, starting, stopping, cleanupUnconfirmed
}

public struct DaemonProfile: Equatable, Sendable {
    public let id: String
    public let configPath: String
    public init(id: String, configPath: String) { self.id = id; self.configPath = configPath }
}

/// A deterministic reducer. The caller executes returned requests and feeds authoritative responses back.
public struct DaemonLifecycle: Sendable {
    public private(set) var reason: String?
    public private(set) var state: LifecycleState = .unknown
    public private(set) var instance: String?
    public private(set) var session: DaemonSession?
    public private(set) var guardsSupported = false
    public private(set) var actionError: String?
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
        reason = response.status.LastError
        if let error = response.error {
            if !handshake { actionError = error }
            replacement = nil
            pending = false
            if !["invalid_configuration", "ikev2_requires_foreground_user_session"].contains(error) {
                state = .cleanupUnconfirmed
                return nil
            }
        }
        // Start acceptance completes the request even while the session is connecting.
        if state == .starting { pending = false }
        if response.status.cleanupConfirmed {
            state = .stopped
            pending = false
            if !restarted, let next = replacement {
                replacement = nil
                return connect(next)
            }
        } else {
            switch response.status.State {
            case "connecting": state = .connecting
            case "connected": state = .connected
            case "reconnecting": state = .reconnecting
            case "stopping": state = .stopping
            case "failed": state = .failed
            default: state = .unknown
            }
        }
        return nil
    }

    public mutating func connect(_ profile: DaemonProfile) -> DaemonRequest? {
        guard !pending, guardsSupported, let instance else { return nil }
        if [.connecting, .connected, .reconnecting, .failed].contains(state), session?.active == true {
            guard session?.profile_id != profile.id else { return nil }
            guard let request = disconnect() else { return nil }
            replacement = profile
            return request
        }
        guard state == .stopped, profile.configPath.hasPrefix("/") else { return nil }
        actionError = nil
        pending = true
        state = .starting
        return DaemonRequest(command: "start", instance: instance, config: profile.configPath)
    }

    public mutating func disconnect() -> DaemonRequest? {
        guard !pending, guardsSupported, state != .unknown, state != .starting,
              let instance, let session, session.active, !session.id.isEmpty else { return nil }
        actionError = nil
        pending = true
        state = .stopping
        return DaemonRequest(command: "stop", instance: instance, session: session.id)
    }
}
