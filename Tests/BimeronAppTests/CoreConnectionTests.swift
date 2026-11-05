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
    func setStartError(_ error: String?) { startError = error }
    func enablePinnedMetadata() { pinnedMetadata = true }
    func setFailStop() { failStop = true }
    func exchange(_ request: DaemonRequest) throws -> DaemonResponse {
        requests.append(request)
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
    #expect(!connection.canStart)
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
    #expect(!connection.canStart)
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
    #expect(await fixture.commands() == ["hello"])
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

@Test func installerManifestRejectsWrongIdentityAndPackage() throws {
    let valid: [String: Any] = ["revision": "pinned", "owner_uid": 501, "production_shipping": false,
                                "provenance": "local-development-untrusted", "package_sha256": "digest"]
    func permits(_ object: [String: Any]) throws -> Bool {
        let manifest = try JSONDecoder().decode(BundledCoreManifest.self,
                                                from: JSONSerialization.data(withJSONObject: object))
        return manifest.permitsOpening(revision: "pinned", ownerUID: 501, packageSHA256: "digest")
    }
    #expect(try permits(valid))
    for (key, value) in [("revision", "other" as Any), ("owner_uid", 502 as Any),
                         ("production_shipping", true as Any), ("provenance", "trusted" as Any),
                         ("package_sha256", "tampered" as Any)] {
        var invalid = valid
        invalid[key] = value
        #expect(try !permits(invalid))
    }
}
