import BimeronModel
import BimeronDaemon
import Foundation
import Testing
@testable import BimeronApp

private actor ConnectionFixture {
    var requests: [DaemonRequest] = []
    var connected = false
    var stopping = false
    func adoptStoppingSession() { connected = true; stopping = true }
    var failedInactive = false
    func failInactive() { connected = false; failedInactive = true }
    var failStop = false
    var delayStop = false
    func setDelayStop() { delayStop = true }
    var startError: String?
    var pinnedMetadata = false
    var unavailable = false
    func disappear() { unavailable = true }
    func setStartError(_ error: String?) { startError = error }
    func enablePinnedMetadata() { pinnedMetadata = true }
    func setFailStop() { failStop = true }
    func exchange(_ request: DaemonRequest) throws -> DaemonResponse {
        requests.append(request)
        if unavailable { throw DaemonError.unavailable }
        if request.command == "start", startError == nil { connected = true }
        if request.command == "stop", !failStop, !delayStop { connected = false }
        let session: [String: Any] = ["id": "session-1", "active": connected, "profile_id": "owned-profile"]
        var response: [String: Any] = ["version": 1, "id": request.id, "instance": "daemon-1",
                                      "daemon_session_guards": true,
                                      "status": ["State": failedInactive ? "failed" : (stopping ? "stopping" : (connected ? "connected" : "disconnected")), "Session": session]]
        if failedInactive { response["status"] = ["State": "failed", "Session": session, "LastError": "old failure"] }
        if pinnedMetadata {
            response["core"] = ["revision": "baf3d0e1b061b6f1210b0d9aa040c9512fe646a1", "modified": false, "platform": "darwin"]
        }
        if request.command == "start", let startError { response["error"] = startError }
        if request.command == "stop", failStop { response["error"] = "cleanup_failed" }
        return try DaemonProtocol.decode(JSONSerialization.data(withJSONObject: response) + Data([10]), request: request)
    }
    func commands() -> [String] { requests.map(\.command) }
    func config() -> String? { requests.first { $0.command == "start" }?.config }
}

@Test @MainActor func connectionUsesSelectedFileAndRequiresConfirmedStop() async throws {
    let fixture = ConnectionFixture()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }))
    #expect(connection.state == .unknown)
    #expect(connection.canStart)
    await connection.refresh()
    #expect(connection.canStart)
    let file = URL(fileURLWithPath: "/tmp/isolated profile.conf")
    await connection.start(file: file)
    #expect(connection.state == .connected)
    #expect(await fixture.config() == file.path)
    await connection.start(file: file)
    #expect(await fixture.commands().filter { $0 == "start" }.count == 1)
    await fixture.setFailStop()
    await connection.stop()
    #expect(connection.state == .cleanupUnconfirmed)
    #expect(!connection.canStart)
}

@Test @MainActor func reopeningAdoptsActiveSessionWithoutStarting() async throws {
    let fixture = ConnectionFixture()
    let client = DaemonClient(exchange: { try await fixture.exchange($0) })
    let first = CoreConnection(client: client)
    await first.refresh()
    await first.start(file: URL(fileURLWithPath: "/tmp/isolated.conf"))
    let reopened = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }))
    await reopened.refresh()
    #expect(reopened.state == .connected)
    #expect(reopened.canStop)
    #expect(await fixture.commands().filter { $0 == "start" }.count == 1)
    await reopened.stop()
    #expect(reopened.state == .stopped)
}

@Test @MainActor func incompatibleDaemonCannotBecomeReady() async {
    let fixture = ConnectionFixture()
    let client = DaemonClient(exchange: { try await fixture.exchange($0) }, expectedRevision: CoreConnection.revision)
    let connection = CoreConnection(client: client)
    await connection.refresh()
    #expect(connection.state == .unknown)
    #expect(connection.canStart)
    #expect(await fixture.commands() == ["hello"])
}

@Test @MainActor func rejectedStartSurvivesSuccessfulReconcileUntilNextAction() async {
    for error in ["invalid_configuration", "ikev2_requires_foreground_user_session"] {
        let fixture = ConnectionFixture()
        await fixture.setStartError(error)
        let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }))
        await connection.refresh()
        await connection.start(file: URL(fileURLWithPath: "/tmp/rejected.conf"))
        #expect(connection.state == .stopped)
        #expect(connection.actionError == error)
        #expect(connection.actionErrorKey != nil)
        await connection.refresh()
        #expect(connection.state == .stopped)
        #expect(connection.actionError == error)
        #expect(connection.canStart)
        await fixture.setStartError(nil)
        await connection.start(file: URL(fileURLWithPath: "/tmp/corrected.conf"))
        #expect(connection.state == .connected)
        #expect(connection.actionError == nil)
    }
}

@Test @MainActor func pinnedBuildMetadataAllowsReadiness() async {
    let fixture = ConnectionFixture()
    await fixture.enablePinnedMetadata()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) },
                                                        expectedRevision: CoreConnection.revision))
    await connection.refresh()
    #expect(connection.state == .stopped)
    #expect(connection.canStart)
    #expect(await fixture.commands() == ["hello", "events"])
}

@Test @MainActor func daemonIKEv2StartIsBlockedBeforeAnyExchange() async throws {
    let model = AppModel(coreCLI: nil)
    let profile = StoredProfile(document: try ConfigDocument("[Profile]\nName = IKEv2 fixture\n[IKEv2]\nServer = vpn.example.invalid\n"))
    model.profiles = [profile]
    model.selectedID = profile.id
    #expect(model.selectedProfileStartErrorKey != nil)
    await model.startSelectedProfile()
    #expect(model.alertMessage == model.t("IKEv2 is unavailable through daemon Start. Select another protocol."))
    #expect(model.connection.state == .unknown)
}


private actor LaunchSpy {
    var count = 0
    func called() { count += 1 }
}

@Test @MainActor func cancelledPromptAndHandshakeTimeoutNeverStart() async {
    for failure in [CoreLauncher.Failure.cancelled, .failed, .timeout] {
        let spy = LaunchSpy()
        let connection = CoreConnection(
            client: DaemonClient(exchange: { _ in throw DaemonError.unavailable }),
            launch: {
                await spy.called()
                if failure != .timeout { throw failure }
            }, waitAttempts: 2, pause: {})
        await connection.start(file: URL(fileURLWithPath: "/tmp/test.conf"))
        #expect(connection.launchError == failure)
        #expect(connection.statusKey == "Not connected")
        #expect(connection.isQuietIdle)
        #expect(connection.actionErrorKey != nil)
        #expect(!connection.active)
        #expect(await spy.count == 1)
    }
}

@Test @MainActor func incompatibleRevisionNeverPromptsOrStarts() async {
    let fixture = ConnectionFixture()
    let spy = LaunchSpy()
    let connection = CoreConnection(
        client: DaemonClient(exchange: { try await fixture.exchange($0) }, expectedRevision: CoreConnection.revision),
        launch: { await spy.called() })
    await connection.start(file: URL(fileURLWithPath: "/tmp/test.conf"))
    #expect(connection.launchError == .incompatible)
    #expect(await spy.count == 0)
    #expect(await fixture.commands() == ["hello"])
}

@Test @MainActor func tamperedLaunchPayloadIsRejectedBeforePrompt() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("tampered".utf8).write(to: directory.appending(path: "bimeron-core"))
    let manifest = BundledCoreManifest(sha256: String(repeating: "0", count: 64),
        detach_sha256: String(repeating: "0", count: 64), revision: CoreConnection.revision,
        production_shipping: false, provenance: "local-development-untrusted", version: "0.1.0-ba26-dev")
    #expect(throws: CoreLauncher.Failure.failed) {
        try CoreLauncher.verifyPayloads(binaries: directory, manifest: manifest)
    }
}

@Test(arguments: ["retry reason", "macos_network_setup_failed: networksetup command failed: exit status 1"])
@MainActor func reconnectingStatusAndEventReasonArePreserved(reason: String) async throws {
    let client = DaemonClient(exchange: { request in
        let body: [String: Any] = ["version": 1, "id": request.id, "instance": "instance",
            "daemon_session_guards": true,
            "status": ["State": "reconnecting", "LastError": reason],
            "cursor": 1, "events": [["sequence": 1, "event": ["Time": "2026-11-05T00:00:00Z",
                "State": "reconnecting", "Message": "Retry", "LastError": reason]]]]
        return try DaemonProtocol.decode(JSONSerialization.data(withJSONObject: body) + Data([10]), request: request)
    })
    let connection = CoreConnection(client: client)
    await connection.refresh()
    #expect(connection.reachable)
    #expect(connection.state == .reconnecting)
    #expect(connection.statusKey == "Core: reconnecting")
    #expect(connection.reason == reason)
    #expect(connection.journal.map(\.message) == ["[reconnecting] Retry Reason: \(reason)"])
    await connection.refresh()
    #expect(connection.journal.count == 1)
}

@Test @MainActor func vanishedIncompatibleDaemonAllowsLaunch() async {
    let fixture = ConnectionFixture()
    let spy = LaunchSpy()
    let connection = CoreConnection(
        client: DaemonClient(exchange: { try await fixture.exchange($0) }, expectedRevision: CoreConnection.revision),
        launch: { await spy.called(); throw CoreLauncher.Failure.cancelled }, pause: {})
    await connection.start(file: URL(fileURLWithPath: "/tmp/test.conf"))
    #expect(connection.launchError == .incompatible)
    await fixture.disappear()
    await connection.refresh()
    #expect(connection.launchError == nil)
    await connection.start(file: URL(fileURLWithPath: "/tmp/test.conf"))
    #expect(await spy.count == 1)
    #expect(connection.launchError == .cancelled)
}

@Test @MainActor func crashedActiveDaemonDoesNotLeaveStartDisabled() async {
    let fixture = ConnectionFixture()
    let spy = LaunchSpy()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }),
        launch: { await spy.called(); throw CoreLauncher.Failure.cancelled }, pause: {})
    await connection.refresh()
    await connection.start(file: URL(fileURLWithPath: "/tmp/test.conf"))
    #expect(connection.active)
    await fixture.disappear()
    await connection.refresh()
    #expect(connection.state == .unknown)
    #expect(!connection.active)
    #expect(connection.statusKey == "Core: unknown or unavailable")
    #expect(!connection.isQuietIdle)
    #expect(connection.profileName == nil)
    #expect(connection.reason == nil)
    #expect(connection.canStart)
    await connection.start(file: URL(fileURLWithPath: "/tmp/test.conf"))
    #expect(await spy.count == 1)
}

private actor RetryHelloFixture {
    var hellos = 0
    func exchange(_ request: DaemonRequest) throws -> DaemonResponse {
        if request.command == "hello" {
            hellos += 1
            if hellos == 1 { throw DaemonError.unavailable }
        }
        let body: [String: Any] = ["version": 1, "id": request.id, "instance": "instance",
            "daemon_session_guards": true, "status": ["State": "disconnected"]]
        return try DaemonProtocol.decode(JSONSerialization.data(withJSONObject: body) + Data([10]), request: request)
    }
}

@Test @MainActor func singleMissedHandshakeDoesNotPrompt() async {
    let fixture = RetryHelloFixture()
    let spy = LaunchSpy()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }),
        launch: { await spy.called() }, pause: {})
    await connection.start(file: URL(fileURLWithPath: "/tmp/test.conf"))
    #expect(await spy.count == 0)
    #expect(await fixture.hellos == 2)
    #expect(connection.reachable)
}

@Test @MainActor func reachableDaemonClearsEarlierLaunchError() async {
    let fixture = ConnectionFixture()
    let connection = CoreConnection(
        client: DaemonClient(exchange: { try await fixture.exchange($0) }, expectedRevision: CoreConnection.revision))
    await connection.start(file: URL(fileURLWithPath: "/tmp/test.conf"))
    #expect(connection.launchError == .incompatible)
    await fixture.enablePinnedMetadata()
    await connection.refresh()
    #expect(connection.reachable)
    #expect(connection.launchError == nil)
}

@Test @MainActor func invalidDroppedBatchDoesNotRepeatGapLines() async {
    let connection = CoreConnection(client: DaemonClient(exchange: { request in
        let body: [String: Any] = ["version": 1, "id": request.id, "instance": "instance",
            "daemon_session_guards": true, "status": ["State": "disconnected"],
            "dropped": true, "cursor": 1,
            "events": [["sequence": 2, "event": ["Time": "now", "State": "connected", "Message": "bad sequence"]]]]
        return try DaemonProtocol.decode(JSONSerialization.data(withJSONObject: body) + Data([10]), request: request)
    }))
    await connection.refresh()
    await connection.refresh()
    #expect(connection.journal.isEmpty)
}

@Test @MainActor func reachableUnknownSessionStateNeverPrompts() async {
    for state in ["disconnected", "future-state"] {
        let spy = LaunchSpy()
        let connection = CoreConnection(client: DaemonClient(exchange: { request in
            let body: [String: Any] = ["version": 1, "id": request.id, "instance": "instance",
                "daemon_session_guards": true,
                "status": ["State": state, "Session": ["id": "live", "active": true]]]
            return try DaemonProtocol.decode(JSONSerialization.data(withJSONObject: body) + Data([10]), request: request)
        }), launch: { await spy.called() }, pause: {})
        await connection.start(file: URL(fileURLWithPath: "/tmp/test.conf"))
        #expect(connection.state == .unknown)
        #expect(connection.reachable)
        #expect(await spy.count == 0)
    }
}

@Test @MainActor func incompatibleGuardedHelloKeepsRefusalVisible() async {
    let spy = LaunchSpy()
    let connection = CoreConnection(client: DaemonClient(exchange: { request in
        let body: [String: Any] = ["version": 1, "id": request.id, "instance": "instance",
            "daemon_session_guards": true, "error": "unsupported_client",
            "status": ["State": "disconnected"]]
        return try DaemonProtocol.decode(JSONSerialization.data(withJSONObject: body) + Data([10]), request: request)
    }), launch: { await spy.called() })
    await connection.start(file: URL(fileURLWithPath: "/tmp/test.conf"))
    #expect(!connection.reachable)
    #expect(connection.launchError == .incompatible)
    #expect(await spy.count == 0)
}

@Test @MainActor func firstStartIdleStatusIsCalmWhenCoreIsAbsent() async {
    let connection = CoreConnection(client: DaemonClient(exchange: { _ in throw DaemonError.unavailable }))
    #expect(connection.statusKey == "Not connected")
    #expect(connection.isQuietIdle)
    await connection.refresh()
    #expect(connection.statusKey == "Not connected")
    #expect(connection.isQuietIdle)
    #expect(connection.canStart)
}

private actor FailedSessionFixture {
    var started = false
    var failStart = false
    func failOnStart() { failStart = true }
    var commands: [String] = []
    func exchange(_ request: DaemonRequest) throws -> DaemonResponse {
        commands.append(request.command)
        if request.command == "start" { started = true }
        let status: [String: Any] = ["State": started && !failStart ? "connecting" : "failed",
            "LastError": started && !failStart ? "" : "macos_network_setup_failed: cannot set network service DNS",
            "Session": ["id": "session", "active": started && !failStart]]
        let body: [String: Any] = ["version": 1, "id": request.id, "instance": "instance",
            "daemon_session_guards": true, "status": status]
        return try DaemonProtocol.decode(JSONSerialization.data(withJSONObject: body) + Data([10]), request: request)
    }
}

@Test @MainActor func inactiveFailedSessionCanRetryWithoutLaunchingCore() async {
    let fixture = FailedSessionFixture()
    let spy = LaunchSpy()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }),
        launch: { await spy.called() })
    await connection.refresh()
    #expect(connection.state == .failed)
    #expect(!connection.active)
    #expect(connection.canStart)
    #expect(!connection.canStop)
    #expect(connection.statusKey == "Not connected")
    #expect(connection.isQuietIdle)
    #expect(connection.reason == nil)
    await connection.refresh()
    #expect(connection.statusKey == "Not connected")
    #expect(connection.reason == nil)
    await connection.start(file: URL(fileURLWithPath: "/tmp/retry.conf"))
    #expect(await fixture.commands.filter { $0 == "start" }.count == 1)
    #expect(await spy.count == 0)
    #expect(connection.state == .connecting)
    #expect(connection.reason == "")
}

private actor StopRaceFixture {
    var completed = false
    var failDuringStop = false
    var stops = 0
    func finishBeforeStop() { completed = true }
    func failOnStop() { failDuringStop = true }
    func exchange(_ request: DaemonRequest) throws -> DaemonResponse {
        let stopping = request.command == "stop"
        if stopping { stops += 1; completed = true }
        var body: [String: Any] = ["version": 1, "id": request.id, "instance": "instance",
            "daemon_session_guards": true,
            "status": ["State": completed ? "failed" : "connecting",
                "LastError": completed ? "networksetup command failed" : "",
                "Session": ["id": "session", "active": !completed]]]
        if stopping && failDuringStop { body["error"] = "session_stop_failed" }
        return try DaemonProtocol.decode(JSONSerialization.data(withJSONObject: body) + Data([10]), request: request)
    }
}

@Test @MainActor func stopDoesNotMutateAnAlreadyFinishedSession() async {
    let fixture = StopRaceFixture()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }))
    await connection.refresh()
    #expect(connection.canStop)
    await fixture.finishBeforeStop()
    await connection.stop()
    #expect(await fixture.stops == 0)
    #expect(connection.state == .failed)
    #expect(connection.canStart)
    #expect(connection.reason == "networksetup command failed")
    #expect(connection.actionErrorKey == nil)
}

@Test @MainActor func failureDuringStopExplainsTheActionInRussian() async {
    let fixture = StopRaceFixture()
    await fixture.failOnStop()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }))
    await connection.refresh()
    await connection.stop()
    #expect(await fixture.stops == 1)
    #expect(connection.actionError == "session_stop_failed")
    #expect(connection.actionErrorKey == "Core could not finish stopping the connection. Check the failure reason and connection status.")
    #expect(connection.reason == "networksetup command failed")
    await connection.refresh()
    #expect(connection.canStart)
    #expect(connection.actionErrorKey.map { Localization.text($0, language: "ru") } == "Core не удалось завершить остановку подключения. Проверьте причину ошибки и состояние подключения.")
}

@Test @MainActor func aboutRunningStatusTracksReachability() async {
    let fixture = ConnectionFixture()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }))
    #expect(connection.runningStatusKey == "Core not running")
    await connection.refresh()
    #expect(connection.runningStatusKey == "Core running")
    await fixture.disappear()
    await connection.refresh()
    #expect(connection.runningStatusKey == "Core not running")
    #expect(connection.statusKey == "Not connected")
}

@Test @MainActor func confirmedStopClearsActiveSessionLossWarning() async {
    let fixture = ConnectionFixture()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }))
    await connection.refresh()
    await connection.start(file: URL(fileURLWithPath: "/tmp/test.conf"))
    await connection.stop()
    await fixture.disappear()
    await connection.refresh()
    #expect(connection.statusKey == "Not connected")
    #expect(connection.isQuietIdle)
}

@Test @MainActor func failureObservedWhileRunningShowsReason() async {
    let fixture = StopRaceFixture()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }))
    await connection.refresh()
    #expect(connection.state == .connecting)
    await fixture.finishBeforeStop()
    await connection.refresh()
    #expect(connection.statusKey == "Core: connection failed")
    #expect(connection.reason == "networksetup command failed")
    await connection.refresh()
    #expect(connection.reason == "networksetup command failed")
}

@Test @MainActor func failureAfterOwnStartIsShownEvenWithoutObservedActiveState() async {
    let fixture = FailedSessionFixture()
    await fixture.failOnStart()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }))
    await connection.refresh()
    #expect(connection.statusKey == "Not connected")
    await connection.start(file: URL(fileURLWithPath: "/tmp/retry.conf"))
    #expect(connection.statusKey == "Core: connection failed")
    #expect(connection.reason == "macos_network_setup_failed: cannot set network service DNS")
}

@Test @MainActor func initialActiveSessionsAreAdoptedInEveryConnectionPhase() async {
    for phase in ["connecting", "connected", "reconnecting"] {
        let connection = CoreConnection(client: DaemonClient(exchange: { request in
            let body: [String: Any] = ["version": 1, "id": request.id, "instance": "instance",
                "daemon_session_guards": true,
                "status": ["State": phase, "Session": ["id": "active", "active": true, "profile_name": "Adopted"]]]
            return try DaemonProtocol.decode(JSONSerialization.data(withJSONObject: body) + Data([10]), request: request)
        }))
        await connection.refresh()
        #expect(connection.active)
        #expect(connection.profileName == "Adopted")
        #expect(connection.statusKey == "Core: " + phase)
        #expect(connection.canStop)
        #expect(!connection.canStart)
    }
}

@Test @MainActor func reopeningWithoutObservedSessionKeepsHistoricalFailureQuiet() async {
    let fixture = ConnectionFixture()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }))
    let monitor = Task { await connection.monitor() }
    while !connection.reachable { await Task.yield() }
    monitor.cancel()
    await monitor.value
    await fixture.failInactive()
    await connection.refresh()
    #expect(connection.statusKey == "Not connected")
    #expect(connection.reason == nil)
    #expect(connection.canStart)
}

private actor SlowTelemetryFixture {
    let phase: String
    var stopped = false
    var eventWaiter: CheckedContinuation<Void, Never>?
    var commands: [String] = []
    init(phase: String) { self.phase = phase }
    func releaseEvents() { eventWaiter?.resume(); eventWaiter = nil }
    func exchange(_ request: DaemonRequest) async throws -> DaemonResponse {
        commands.append(request.command)
        if request.command == "events" {
            await withCheckedContinuation { eventWaiter = $0 }
        }
        if request.command == "stop" { stopped = true }
        let body: [String: Any] = ["version": 1, "id": request.id, "instance": "instance",
            "daemon_session_guards": true,
            "status": ["State": stopped ? "disconnected" : phase,
                "LastError": stopped ? "" : "network_unavailable",
                "Session": ["id": "session", "active": !stopped]]]
        return try DaemonProtocol.decode(JSONSerialization.data(withJSONObject: body) + Data([10]), request: request)
    }
}

@Test @MainActor func slowTelemetryDoesNotDisableStopDuringConnectionProgress() async {
    for phase in ["connecting", "reconnecting"] {
        let fixture = SlowTelemetryFixture(phase: phase)
        let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }))
        let refresh = Task { await connection.refresh() }
        while await fixture.eventWaiter == nil { await Task.yield() }
        #expect(!connection.busy)
        #expect(connection.canStop)
        #expect(!connection.canStart)
        #expect(connection.reason == "network_unavailable")
        // A second monitor refresh must not start another telemetry batch.
        await connection.refresh()
        #expect(await fixture.commands.filter { $0 == "events" }.count == 1)
        await connection.stop()
        #expect(await fixture.commands.filter { $0 == "stop" }.count == 1)
        #expect(connection.state == .stopped)
        await fixture.releaseEvents()
        await refresh.value
        #expect(connection.state == .stopped)
        #expect(connection.canStart)
    }
}

private actor SlowHandshakeFixture {
    var phase: String
    var holdHello = false
    var waiter: CheckedContinuation<Void, Never>?
    var commands: [String] = []
    init(phase: String) { self.phase = phase }
    func suspendNextHello() { holdHello = true }
    func releaseHello() { waiter?.resume(); waiter = nil }
    func exchange(_ request: DaemonRequest) async throws -> DaemonResponse {
        commands.append(request.command)
        if request.command == "hello", holdHello {
            holdHello = false
            await withCheckedContinuation { waiter = $0 }
        }
        if request.command == "stop" { phase = "disconnected" }
        if request.command == "start" { phase = "connecting" }
        let body: [String: Any] = ["version": 1, "id": request.id, "instance": "instance",
            "daemon_session_guards": true,
            "status": ["State": phase, "Session": ["id": "session", "active": phase != "disconnected"]]]
        return try DaemonProtocol.decode(JSONSerialization.data(withJSONObject: body) + Data([10]), request: request)
    }
}

@Test @MainActor func backgroundHandshakeDoesNotDisableOrDropUserActions() async {
    for initialPhase in ["reconnecting", "disconnected"] {
        let fixture = SlowHandshakeFixture(phase: initialPhase)
        let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }))
        await connection.refresh()
        await fixture.suspendNextHello()
        let refresh = Task { await connection.refresh() }
        while await fixture.waiter == nil { await Task.yield() }
        #expect(!connection.busy)
        #expect(connection.canStop == (initialPhase == "reconnecting"))
        #expect(connection.canStart == (initialPhase == "disconnected"))
        let action = Task {
            if initialPhase == "reconnecting" { await connection.stop() }
            else { await connection.start(file: URL(fileURLWithPath: "/tmp/test.conf")) }
        }
        while !connection.busy { await Task.yield() }
        await fixture.releaseHello()
        await action.value
        await refresh.value
        let command = initialPhase == "reconnecting" ? "stop" : "start"
        #expect(await fixture.commands.filter { $0 == command }.count == 1)
        #expect(!connection.busy)
        #expect(connection.state == (initialPhase == "reconnecting" ? .stopped : .connecting))
    }
}

@Test @MainActor func quitWaitsForCleanupAndPreservesStopFailures() async {
    for fails in [false, true] {
        let fixture = ConnectionFixture()
        let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }))
        await connection.refresh()
        await connection.start(file: URL(fileURLWithPath: "/tmp/quit-fixture.conf"))
        if fails { await fixture.setFailStop() }
        let error = await connection.stopForQuit()
        #expect((error != nil) == fails)
        #expect((connection.state == .stopped) == !fails)
        #expect(await fixture.commands().filter { $0 == "stop" }.count == 1)
        #expect(await fixture.commands().allSatisfy { $0 != "shutdown" })
    }
}

@Test @MainActor func quitTimeoutDoesNotClaimCleanup() async {
    let fixture = ConnectionFixture()
    await fixture.setDelayStop()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }),
                                    pause: { try await Task.sleep(for: .milliseconds(2)) })
    await connection.refresh()
    await connection.start(file: URL(fileURLWithPath: "/tmp/quit-fixture.conf"))
    let error = await connection.stopForQuit(timeout: .milliseconds(1))
    #expect(error == "VPN could not be stopped in time. The app will stay open.")
    #expect(connection.active)
    #expect(connection.state != .stopped)
}

@Test @MainActor func quitReportsInactiveStopFailureWithoutWaiting() async {
    let fixture = StopRaceFixture()
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }),
                                    pause: { Issue.record("Failed Stop must not wait for timeout") })
    await connection.refresh()
    let outcome = await QuitDecision.resolve(.disconnect) { await connection.stopForQuit() }
    #expect(outcome == .error("Core could not finish stopping the connection. Check the failure reason and connection status."))
    #expect(await fixture.stops == 1)
    #expect(connection.actionError == nil)
    #expect(connection.state == .failed)
    #expect(!connection.active)
}

@Test @MainActor func quitIgnoresStaleActionErrorBeforeStop() async {
    let fixture = ConnectionFixture()
    await fixture.setStartError("invalid_configuration")
    let connection = CoreConnection(client: DaemonClient(exchange: { try await fixture.exchange($0) }),
                                    pause: { try await Task.sleep(for: .milliseconds(2)) })
    await connection.refresh()
    await connection.start(file: URL(fileURLWithPath: "/tmp/rejected.conf"))
    await fixture.adoptStoppingSession()
    await connection.refreshForQuit()
    // The prior Start error survives reconciliation while Stop is unavailable.
    #expect(connection.actionErrorKey != nil)
    #expect(!connection.canStop)
    let outcome = await QuitDecision.resolve(.disconnect) { await connection.stopForQuit(timeout: .milliseconds(1)) }
    #expect(outcome == .error("VPN could not be stopped in time. The app will stay open."))
    #expect(await fixture.commands().filter { $0 == "stop" }.isEmpty)
    #expect(connection.state == .stopping)
}
