import Foundation

public enum SSHAuthError: Error, Equatable, Sendable {
    case invalidScope, invalidChallenge, staleChallenge, invalidAnswers, requestTooLarge
    case runtimeSendingDisabled
}

public struct SSHAuthScope: Equatable, Sendable {
    public let attempt: UUID
    public let instance: String
    public let session: String

    public init(attempt: UUID, instance: String, session: String) throws {
        guard !instance.isEmpty, !session.isEmpty else { throw SSHAuthError.invalidScope }
        self.attempt = attempt
        self.instance = instance
        self.session = session
    }
}

/// A typed boundary for an already authenticated, correlated control response.
/// Decode JSON strictly in the control adapter; render prompts as untrusted plain text.
public struct SSHAuthChallenge: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Kind: String, Sendable, CaseIterable {
        case keyPassphrase = "key_passphrase"
        case password
        case keyboardInteractive = "keyboard_interactive"
    }

    public let id: String
    public let kind: Kind
    public let prompts: [String]
    public let echo: [Bool]

    public init(id: String, kind: String, prompts: [String], echo: [Bool]) throws {
        guard id.utf8.count == 32,
              id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let kind = Kind(rawValue: kind), (1...8).contains(prompts.count),
              prompts.count == echo.count, prompts.allSatisfy({ $0.utf8.count <= 256 }) else {
            throw SSHAuthError.invalidChallenge
        }
        self.id = id
        self.kind = kind
        self.prompts = prompts
        self.echo = echo
    }

    public var description: String { "SSHAuthChallenge(kind: \(kind.rawValue), prompts: \(prompts.count), content: <redacted>)" }
    public var debugDescription: String { description }
}

/// Local presentation state only. This type cannot encode or send an RPC.
public struct SSHAuthState: Sendable, CustomDebugStringConvertible {
    public let scope: SSHAuthScope
    public private(set) var challenge: SSHAuthChallenge?
    public private(set) var deadline: Date?
    private var retiredIDs: Set<String> = []
    private var cancelled = false

    public init(scope: SSHAuthScope) { self.scope = scope }

    /// The caller must supply the current local scope, not one copied from a stale poll.
    /// Core starts its timer before polling; this local ceiling is not proof of validity.
    public mutating func observe(
        _ incoming: SSHAuthChallenge?, version: Int, currentScope: SSHAuthScope,
        responseInstance: String, responseSession: String?, now: Date
    ) throws {
        expire(now: now)
        guard !cancelled, currentScope == scope, responseInstance == scope.instance,
              responseSession == scope.session, version == 1 else {
            cancel()
            throw SSHAuthError.staleChallenge
        }
        guard let incoming else { retire(); return }
        if let challenge, challenge.id == incoming.id {
            guard challenge == incoming else {
                retire()
                throw SSHAuthError.invalidChallenge
            }
            return // Repeated polls never move the original deadline.
        }
        retire()
        guard !retiredIDs.contains(incoming.id) else { throw SSHAuthError.staleChallenge }
        challenge = incoming
        deadline = now.addingTimeInterval(120)
    }

    public mutating func expire(now: Date) {
        if let deadline, now >= deadline { retire() }
    }

    /// Dismiss locally. Core has no auth_cancel command; session stop belongs to its owner.
    public mutating func cancel() { retire(); cancelled = true }

    /// Checks transient input without storing it or producing an encoded request.
    public mutating func validateAnswers(
        _ answers: [String], challengeID: String, currentScope: SSHAuthScope, now: Date
    ) throws {
        expire(now: now)
        guard currentScope == scope else { cancel(); throw SSHAuthError.staleChallenge }
        guard !cancelled, let challenge, challenge.id == challengeID else { throw SSHAuthError.staleChallenge }
        guard answers.count == challenge.prompts.count,
              answers.allSatisfy({ $0.utf8.count <= 1024 }) else { throw SSHAuthError.invalidAnswers }
        // Count a conservative v1 envelope including newline; never construct a sendable RPC.
        let fixedBytes = 100 // version, command, challenge_id (32 bytes), answers, punctuation, newline
        let size = fixedBytes + answers.reduce(0) { $0 + Self.jsonStringUpperBound($1) + 1 }
        guard size <= 16 * 1024 else { throw SSHAuthError.requestTooLarge }
    }

    /// Unconditional until Core supports binding auth_reply to instance AND session.
    public func requireRuntimeSending() throws { throw SSHAuthError.runtimeSendingDisabled }

    public var debugDescription: String { "SSHAuthState(pending: \(challenge != nil), cancelled: \(cancelled), content: <redacted>)" }

    private mutating func retire() {
        if let challenge { retiredIDs.insert(challenge.id) }
        challenge = nil
        deadline = nil
    }

    private static func jsonStringUpperBound(_ value: String) -> Int {
        value.unicodeScalars.reduce(2) { count, scalar in
            switch scalar.value {
            case 0...31, 0x3C, 0x3E, 0x26, 0x2028, 0x2029: return count + 6
            case 0x22, 0x5C, 0x2F: return count + 2
            default: return count + scalar.utf8.count
            }
        }
    }
}
