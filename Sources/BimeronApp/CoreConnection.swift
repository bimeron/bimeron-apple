import AppKit
import BimeronDaemon
import BimeronStatistics
import CryptoKit
import Foundation
import Observation

@MainActor @Observable final class CoreConnection {
    nonisolated static let revision = "6b0d97a4ac96a903153a57d544751401b98d6909"
    private let client: DaemonClient
    private(set) var state: LifecycleState = .unknown
    private(set) var busy = false
    private(set) var actionError: String?
    private(set) var active = false
    private(set) var profileName: String?
    private let launch: @Sendable () async throws -> Void
    private let pause: @Sendable () async throws -> Void
    private let waitAttempts: Int
    private(set) var launchError: CoreLauncher.Failure?
    private(set) var reachable = false
    private(set) var reason: String?
    private(set) var journal: [LogEntry] = []
    private(set) var statistics: ConnectionStatistics?
    private var eventInstance: String?
    private var cursor: UInt64 = 0
    private var statisticsAdapter: DaemonStatisticsAdapter?

    init(client: DaemonClient = DaemonClient(expectedRevision: CoreConnection.revision),
         launch: @escaping @Sendable () async throws -> Void = { try await CoreLauncher.launch() },
         waitAttempts: Int = 20,
         pause: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) }) {
        self.launch = launch
        self.pause = pause
        self.waitAttempts = waitAttempts
        self.client = client
    }

    var statusKey: String {
        switch state {
        case .unknown: "Core: unknown or unavailable"
        case .stopped: "Core: disconnected"
        case .connected: "Core: connected"
        case .connecting, .starting: "Core: connecting"
        case .reconnecting: "Core: reconnecting"
        case .stopping: "Core: stopping; cleanup pending"
        case .cleanupUnconfirmed: "Core: error; cleanup unconfirmed"
        case .failed: "Core: connection failed"
        }
    }

    var actionErrorKey: String? {
        if let launchError {
            switch launchError {
            case .cancelled: return "Administrator approval was cancelled. Core was not started."
            case .failed: return "Core could not be installed or launched. Check administrator access and the app bundle."
            case .timeout: return "Core did not become ready in time. Try Start again."
            case .incompatible: return "A different or incompatible Core is running. Stop it explicitly before trying again."
            }
        }
        guard let actionError else { return nil }
        switch actionError {
        case "invalid_configuration": return "Core rejected the configuration. Edit or validate the selected profile before trying again."
        case "ikev2_requires_foreground_user_session": return "IKEv2 is unavailable through daemon Start. Select another protocol."
        default: return "Core rejected the action. Check the profile and Core status before trying again."
        }
    }

    var canStart: Bool { !busy && (state == .unknown || (state == .stopped && !active)) }
    var canStop: Bool { !busy && active && ![.unknown, .starting, .stopping].contains(state) }

    func monitor() async {
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: .seconds(1)) } catch { break }
        }
        await client.invalidate()
        state = .unknown
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        await client.reconcile()
        await update()
        await pollTelemetry()
    }

    func start(file: URL) async {
        guard canStart else { return }
        busy = true
        defer { busy = false }
        launchError = nil
        await client.reconcile()
        if await client.incompatible {
            launchError = .incompatible
            await update()
            return
        }
        if await client.state == .unknown {
            try? await pause()
            await client.reconcile()
            if await client.incompatible {
                launchError = .incompatible
                await update()
                return
            }
        }
        if await client.state == .unknown {
            do {
                try await launch()
                for _ in 0..<waitAttempts {
                    await client.reconcile()
                    if await client.incompatible { throw CoreLauncher.Failure.incompatible }
                    if await client.guardsSupported { break }
                    try await pause()
                }
                guard await client.guardsSupported else { throw CoreLauncher.Failure.timeout }
            } catch {
                launchError = (error as? CoreLauncher.Failure) ?? .failed
                await update()
                return
            }
        }
        guard await client.state == .stopped, await client.guardsSupported else {
            await update()
            return
        }
        let path = file.standardizedFileURL.path
        let id = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        await client.connect(DaemonProfile(id: id, configPath: path))
        await update()
    }

    func stop() async {
        guard canStop else { return }
        busy = true
        defer { busy = false }
        await client.disconnect()
        await update()
    }

    private func update() async {
        actionError = await client.actionError
        let supported = await client.guardsSupported
        let observed = await client.state
        state = supported ? observed : .unknown
        reachable = supported
        if reachable { launchError = nil }
        reason = await client.reason
        let session = await client.session
        active = session?.active == true
        profileName = session?.profile_name
    }

    private func pollTelemetry() async {
        guard reachable, let instance = await client.instance else {
            await statisticsAdapter?.invalidate()
            statistics = nil
            return
        }
        if eventInstance != instance { eventInstance = instance; cursor = 0 }
        do {
            let response = try await client.read(DaemonRequest(command: "events", after: cursor))
            guard response.instance == instance, response.error == nil else { return }
            if let next = response.cursor, next >= cursor {
                let events = response.events ?? []
                guard events.allSatisfy({ $0.sequence > cursor && $0.sequence <= next }),
                      zip(events, events.dropFirst()).allSatisfy({ $0.sequence < $1.sequence }) else { return }
                if response.dropped == true { journal.append(LogEntry(message: "Core event history gap")) }
                journal.append(contentsOf: events.map { LogEntry(message: $0.event.line) })
                journal = Array(journal.suffix(500))
                cursor = next
            }
        } catch { /* The next reconciliation determines reachability. */ }
        guard active, let session = await client.session else {
            await statisticsAdapter?.invalidate()
            statistics = nil
            return
        }
        if statisticsAdapter == nil {
            let client = client
            statisticsAdapter = DaemonStatisticsAdapter(
                statistics: ConnectionStatistics(staleAfter: .seconds(10), historyLimit: 60, eventLimit: 0),
                transport: { request in
                    let response = try await client.read(request)
                    // The client already decoded and authenticated the framed response.
                    return try JSONEncoder().encode(response) + Data([10])
                })
        }
        guard let adapter = statisticsAdapter else { return }
        let identity = ConnectionStatistics.Identity(instance: instance, session: session.id)
        if await adapter.statistics.token?.identity != identity { await adapter.confirm(identity) }
        await adapter.poll()
        statistics = await adapter.statistics
    }
}
