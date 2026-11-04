import Foundation
import XCTest
@testable import BimeronDaemon

final class DaemonLifecycleTests: XCTestCase {
    private func response(state: String = "disconnected", profile: String? = nil, active: Bool = false,
                          instance: String = "one", sessionID: String = "session", error: String? = nil, guards: Bool = true) throws -> DaemonResponse {
        var object: [String: Any] = ["version": 1, "id": "test", "instance": instance,
            "daemon_session_guards": guards, "status": ["State": state,
                "Session": ["id": sessionID, "active": active, "profile_id": profile ?? ""]]]
        if let error { object["error"] = error }
        return try JSONDecoder().decode(DaemonResponse.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private struct Manifest: Decodable {
        struct Scenario: Decodable { let id: String; let owner: String; let fixture: String }
        let scenarios: [Scenario]
    }
    private struct Script: Decodable {
        let events: [String]
        let expected_commands: [String]
        let expected_final_state: String
    }

    func testSharedAcceptanceScriptsAtEveryBoundary() throws {
        let root = ProcessInfo.processInfo.environment["BIMERON_ACCEPTANCE_FIXTURE_ROOT"]
            .map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appending(path: "fixtures/acceptance")
        guard FileManager.default.fileExists(atPath: root.appending(path: "manifest.json").path) else {
            XCTFail("D dependency missing: integrate f8988b7 or explicitly set BIMERON_ACCEPTANCE_FIXTURE_ROOT; default CI readiness is not established")
            return
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appending(path: "manifest.json")))
        let scenarios = manifest.scenarios.filter { $0.owner == "C" }
        XCTAssertEqual(Set(scenarios.map(\.id)), ["C-REPEAT", "C-ADOPT", "C-IPC-LOSS", "C-SWITCH", "C-FAILED-STOP"])
        for scenario in scenarios {
            let script = try JSONDecoder().decode(Script.self, from: Data(contentsOf: root.appending(path: scenario.fixture)))
            var lifecycle = DaemonLifecycle()
            _ = lifecycle.observe(try response(), handshake: true)
            var log: [String] = []
            var expected: [String] = []
            var switchPending = false
            for event in script.events {
                var command: DaemonRequest?
                switch event {
                case "request-connect:A":
                    command = lifecycle.connect(DaemonProfile(id: "A", configPath: "/A"))
                    if expected.isEmpty { expected.append("start:A") }
                case "request-switch:B":
                    command = lifecycle.connect(DaemonProfile(id: "B", configPath: "/B"))
                    expected.append("stop"); switchPending = true
                case "request-disconnect":
                    command = lifecycle.disconnect()
                    if !expected.contains("stop") { expected.append("stop") }
                case "observe-connected:A", "observe-connected:B", "observe-connected:existing":
                    command = lifecycle.observe(try response(state: "connected", profile: String(event.split(separator: ":")[1]), active: true))
                case "observe-stopped":
                    command = lifecycle.observe(try response())
                    if switchPending { expected.append("start:B"); switchPending = false }
                case "observe-stop-pending":
                    command = lifecycle.observe(try response(state: "stopping", profile: "A", active: true))
                case "observe-stop-failed":
                    command = lifecycle.observe(try response(state: "failed", profile: "A", active: true, error: "session_stop_failed"))
                    switchPending = false
                case "observe-ipc-lost": lifecycle.loseIPC()
                case "request-adopt": break
                default: XCTFail("Unknown event \(event)")
                }
                if let command { log.append(command.command == "start" ? "start:\(command.config!.dropFirst())" : command.command) }
                XCTAssertEqual(log, expected, "\(scenario.id) at \(event)")
            }
            XCTAssertEqual(log, script.expected_commands, scenario.id)
            let states: [String: LifecycleState] = ["connected": .connected, "stopped": .stopped,
                "unknown": .unknown, "cleanup-unconfirmed": .cleanupUnconfirmed]
            XCTAssertEqual(lifecycle.state, states[script.expected_final_state], scenario.id)
        }
    }

    func testPendingClicksRestartAndAmbiguousTimeoutNeverRetry() throws {
        var lifecycle = DaemonLifecycle()
        _ = lifecycle.observe(try response(), handshake: true)
        let a = DaemonProfile(id: "A", configPath: "/A")
        XCTAssertEqual(lifecycle.connect(a)?.command, "start")
        XCTAssertNil(lifecycle.connect(a))
        XCTAssertNil(lifecycle.disconnect())
        lifecycle.loseIPC() // Timeout/cancellation/IPC failure have the same uncertain outcome.
        XCTAssertEqual(lifecycle.state, .unknown)
        XCTAssertNil(lifecycle.disconnect())
        XCTAssertNil(lifecycle.connect(a))
        XCTAssertNil(lifecycle.observe(try response(state: "connected", profile: "A", active: true), handshake: true))
        XCTAssertEqual(lifecycle.connect(DaemonProfile(id: "B", configPath: "/B"))?.command, "stop")
        XCTAssertNil(lifecycle.disconnect())
        XCTAssertNil(lifecycle.connect(a))
        XCTAssertNil(lifecycle.observe(try response(instance: "two")))
        XCTAssertEqual(lifecycle.state, .stopped)
        XCTAssertNil(lifecycle.connect(a)) // A new hello is required after restart.
        _ = lifecycle.observe(try response(instance: "two"), handshake: true)
        XCTAssertEqual(lifecycle.connect(a)?.instance, "two")
    }

    func testAdoptionUnknownProfileFailedStopAndOldDaemon() throws {
        var lifecycle = DaemonLifecycle()
        XCTAssertNil(lifecycle.observe(try response(state: "connected", active: true), handshake: true))
        XCTAssertEqual(lifecycle.state, .connected)
        XCTAssertEqual(lifecycle.disconnect()?.session, "session")
        _ = lifecycle.observe(try response(state: "failed", active: true, error: "session_stop_failed"))
        XCTAssertEqual(lifecycle.state, .cleanupUnconfirmed)
        XCTAssertNil(lifecycle.connect(DaemonProfile(id: "B", configPath: "/B")))
        _ = lifecycle.observe(try response(), handshake: true)
        _ = lifecycle.observe(try response(guards: false), handshake: true)
        XCTAssertNil(lifecycle.connect(DaemonProfile(id: "B", configPath: "/B")))
        XCTAssertNil(lifecycle.observe(try response()))
        XCTAssertFalse(lifecycle.guardsSupported)
    }

    func testCleanupRequiresDisconnectedAndInactive() throws {
        for observation in [try response(state: "disconnected", active: true), try response(state: "failed")] {
            var lifecycle = DaemonLifecycle()
            _ = lifecycle.observe(observation, handshake: true)
            XCTAssertNil(lifecycle.connect(DaemonProfile(id: "A", configPath: "/A")))
        }
    }
    func testCoreGuardRejectionsNeverRetryOrResumeSwitch() throws {
        // Core local contract: 10e29d5dbb26743776d3586dd1a8b506b4c100f3.
        for error in ["stale_instance", "stale_session", "session_already_running"] {
            var lifecycle = DaemonLifecycle()
            _ = lifecycle.observe(try response(state: "connected", profile: "A", active: true), handshake: true)
            XCTAssertEqual(lifecycle.connect(DaemonProfile(id: "B", configPath: "/B"))?.command, "stop")
            XCTAssertNil(lifecycle.observe(try response(state: "connected", profile: "A", active: true, error: error)))
            XCTAssertEqual(lifecycle.state, .cleanupUnconfirmed)
            XCTAssertNil(lifecycle.observe(try response()))
            XCTAssertEqual(lifecycle.state, .stopped)
        }
    }

    func testAdoptsCoreStatesAndStopsKnownActiveSessions() throws {
        for (core, expected) in [("connecting", LifecycleState.connecting), ("connected", .connected),
                                 ("reconnecting", .reconnecting), ("stopping", .stopping), ("failed", .failed)] {
            var lifecycle = DaemonLifecycle()
            _ = lifecycle.observe(try response(state: core, active: true), handshake: true)
            XCTAssertEqual(lifecycle.state, expected)
            XCTAssertEqual(lifecycle.disconnect()?.session, "session", core)
            XCTAssertNil(lifecycle.disconnect())
        }
    }

    func testAcceptedConnectingCanStopButUnidentifiedStartCannot() throws {
        var lifecycle = DaemonLifecycle()
        _ = lifecycle.observe(try response(), handshake: true)
        XCTAssertEqual(lifecycle.connect(DaemonProfile(id: "A", configPath: "/A"))?.command, "start")
        XCTAssertNil(lifecycle.disconnect())
        _ = lifecycle.observe(try response(state: "connecting", profile: "A", active: true))
        XCTAssertEqual(lifecycle.state, .connecting)
        XCTAssertEqual(lifecycle.disconnect()?.command, "stop")
        _ = lifecycle.observe(try response(state: "stopping", profile: "A", active: true))
        XCTAssertEqual(lifecycle.state, .stopping)
        XCTAssertNil(lifecycle.disconnect())
        XCTAssertNil(lifecycle.connect(DaemonProfile(id: "B", configPath: "/B")))
    }

    func testFailedStopAllowsExplicitRecoveryWithoutResumingReplacement() throws {
        var lifecycle = DaemonLifecycle()
        _ = lifecycle.observe(try response(state: "reconnecting", profile: "A", active: true), handshake: true)
        let b = DaemonProfile(id: "B", configPath: "/B")
        XCTAssertEqual(lifecycle.connect(b)?.command, "stop")
        XCTAssertNil(lifecycle.observe(try response(state: "failed", active: true, error: "session_stop_failed")))
        XCTAssertEqual(lifecycle.state, .cleanupUnconfirmed)
        XCTAssertNil(lifecycle.connect(b))
        XCTAssertEqual(lifecycle.disconnect()?.session, "session")
        XCTAssertNil(lifecycle.disconnect())
        XCTAssertNil(lifecycle.observe(try response()))
        XCTAssertEqual(lifecycle.state, .stopped)
        XCTAssertEqual(lifecycle.connect(b)?.command, "start")
    }

    func testSwitchWaitsForConfirmedCleanupAcrossCoreStates() throws {
        for core in ["connecting", "reconnecting", "failed"] {
            var lifecycle = DaemonLifecycle()
            _ = lifecycle.observe(try response(state: core, profile: "A", active: true), handshake: true)
            XCTAssertEqual(lifecycle.connect(DaemonProfile(id: "B", configPath: "/B"))?.command, "stop")
            for observed in ["stopping", "connected", "disconnected"] {
                XCTAssertNil(lifecycle.observe(try response(state: observed, profile: "A", active: true)))
                XCTAssertNil(lifecycle.disconnect())
                XCTAssertNil(lifecycle.connect(DaemonProfile(id: "C", configPath: "/C")))
            }
            XCTAssertEqual(lifecycle.observe(try response())?.config, "/B")
            XCTAssertNil(lifecycle.observe(try response(state: "connecting", profile: "B", active: true)))
        }
    }

    func testStopRequiresConfirmedActiveSessionIdentity() throws {
        for observation in [try response(state: "connecting", active: true, sessionID: ""),
                            try response(state: "connecting", active: false),
                            try response(state: "unrecognized", active: true)] {
            var lifecycle = DaemonLifecycle()
            _ = lifecycle.observe(observation, handshake: true)
            XCTAssertNil(lifecycle.disconnect())
            XCTAssertNil(lifecycle.connect(DaemonProfile(id: "B", configPath: "/B")))
            XCTAssertNil(lifecycle.observe(try response()))
        }
    }

}
