import BimeronModel
import BimeronDaemon
import Foundation
import Testing
@testable import BimeronApp

private actor ConnectionFixture {
    var requests: [DaemonRequest] = []
    var connected = false
    var failStop = false
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
        if request.command == "stop", !failStop { connected = false }
        let session: [String: Any] = ["id": "session-1", "active": connected, "profile_id": "owned-profile"]
        var response: [String: Any] = ["version": 1, "id": request.id, "instance": "daemon-1",
                                      "daemon_session_guards": true,
                                      "status": ["State": connected ? "connected" : "disconnected", "Session": session]]
        if pinnedMetadata {
            response["core"] = ["revision": "6b0d97a4ac96a903153a57d544751401b98d6909", "modified": false, "platform": "darwin"]
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
        production_shipping: false, provenance: "local-development-untrusted", version: "0.1.0-ba22-dev")
    #expect(throws: CoreLauncher.Failure.failed) {
        try CoreLauncher.verifyPayloads(binaries: directory, manifest: manifest)
    }
}

@Test @MainActor func reconnectingStatusAndEventReasonArePreserved() async throws {
    let client = DaemonClient(exchange: { request in
        let body: [String: Any] = ["version": 1, "id": request.id, "instance": "instance",
            "daemon_session_guards": true,
            "status": ["State": "reconnecting", "LastError": "retry reason"],
            "cursor": 1, "events": [["sequence": 1, "event": ["Time": "2026-11-05T00:00:00Z",
                "State": "reconnecting", "Message": "Retry", "LastError": "retry reason"]]]]
        return try DaemonProtocol.decode(JSONSerialization.data(withJSONObject: body) + Data([10]), request: request)
    })
    let connection = CoreConnection(client: client)
    await connection.refresh()
    #expect(connection.reachable)
    #expect(connection.state == .reconnecting)
    #expect(connection.statusKey == "Core: reconnecting")
    #expect(connection.reason == "retry reason")
    #expect(connection.journal.map(\.message) == ["[reconnecting] Retry Reason: retry reason"])
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
    var commands: [String] = []
    func exchange(_ request: DaemonRequest) throws -> DaemonResponse {
        commands.append(request.command)
        if request.command == "start" { started = true }
        let status: [String: Any] = ["State": started ? "connecting" : "failed",
            "LastError": started ? "" : "macos_network_setup_failed: cannot set network service DNS",
            "Session": ["id": "session", "active": started]]
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
    #expect(connection.reason == "macos_network_setup_failed: cannot set network service DNS")
    await connection.refresh()
    #expect(connection.reason == "macos_network_setup_failed: cannot set network service DNS")
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
