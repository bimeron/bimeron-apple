import Foundation
import XCTest
@testable import BimeronSSHAuth

final class SSHAuthTests: XCTestCase {
    private let id = String(repeating: "a", count: 32)
    private let start = Date(timeIntervalSince1970: 1000)

    private func scope(instance: String = "instance", session: String = "session") throws -> SSHAuthScope {
        try SSHAuthScope(attempt: UUID(), instance: instance, session: session)
    }

    private func challenge(id: String? = nil, prompts: [String] = ["Password"], echo: [Bool] = [false]) throws -> SSHAuthChallenge {
        try SSHAuthChallenge(id: id ?? self.id, kind: "password", prompts: prompts, echo: echo)
    }

    private func observe(_ value: SSHAuthChallenge?, in state: inout SSHAuthState, at time: Date? = nil) throws {
        try state.observe(value, version: 1, currentScope: state.scope,
                          responseInstance: state.scope.instance, responseSession: state.scope.session, now: time ?? start)
    }

    func testKindsAndPromptByteBoundaries() throws {
        for kind in SSHAuthChallenge.Kind.allCases {
            XCTAssertNoThrow(try SSHAuthChallenge(id: id, kind: kind.rawValue, prompts: [""], echo: [true]))
        }
        XCTAssertNoThrow(try challenge(prompts: [String(repeating: "🙂", count: 64)]))
        XCTAssertThrowsError(try challenge(prompts: [String(repeating: "🙂", count: 65)]))
        XCTAssertNoThrow(try challenge(prompts: Array(repeating: "x", count: 8), echo: Array(repeating: false, count: 8)))
        for (prompts, echo) in [([], []), (["x"], []), (Array(repeating: "x", count: 9), Array(repeating: false, count: 9))] {
            XCTAssertThrowsError(try challenge(prompts: prompts, echo: echo))
        }
        for badID in ["", String(repeating: "A", count: 32), String(repeating: "g", count: 32), String(repeating: "a", count: 31), String(repeating: "é", count: 16)] {
            XCTAssertThrowsError(try challenge(id: badID))
        }
        XCTAssertThrowsError(try SSHAuthChallenge(id: id, kind: "unknown", prompts: ["x"], echo: [false]))
        XCTAssertThrowsError(try scope(instance: ""))
        XCTAssertThrowsError(try scope(session: ""))
    }

    func testDuplicatePollCannotExtendOrResurrectExpiredChallenge() throws {
        var state = SSHAuthState(scope: try scope())
        let value = try challenge()
        try observe(value, in: &state)
        try observe(value, in: &state, at: start.addingTimeInterval(119))
        XCTAssertEqual(state.deadline, start.addingTimeInterval(120))
        XCTAssertThrowsError(try observe(value, in: &state, at: start.addingTimeInterval(120)))
        XCTAssertNil(state.challenge)
        XCTAssertNil(state.deadline)
    }

    func testAbsenceReplacementAndChangedContentRetireIDs() throws {
        var state = SSHAuthState(scope: try scope())
        let value = try challenge()
        try observe(value, in: &state)
        try observe(nil, in: &state)
        XCTAssertThrowsError(try observe(value, in: &state))
        let second = try challenge(id: String(repeating: "b", count: 32))
        try observe(second, in: &state)
        XCTAssertThrowsError(try observe(try challenge(id: second.id, prompts: ["Changed"]), in: &state))
        XCTAssertNil(state.challenge)
        XCTAssertThrowsError(try observe(second, in: &state))
        let third = try challenge(id: String(repeating: "c", count: 32))
        let fourth = try challenge(id: String(repeating: "d", count: 32))
        try observe(third, in: &state)
        try observe(fourth, in: &state)
        XCTAssertThrowsError(try observe(third, in: &state))
        XCTAssertNil(state.challenge)
    }

    func testScopeChangesAndCancelInvalidatePermanently() throws {
        for mismatch in 0..<7 {
            var state = SSHAuthState(scope: try scope())
            let value = try challenge()
            try observe(value, in: &state)
            if mismatch == 4 {
                state.cancel()
            } else {
                let current: SSHAuthScope
                if mismatch == 0 { current = try scope() }
                else if mismatch == 5 {
                    current = try SSHAuthScope(attempt: state.scope.attempt, instance: "instance", session: "new-session")
                } else { current = state.scope }
                XCTAssertThrowsError(try state.observe(value, version: mismatch == 1 ? 2 : 1,
                    currentScope: current, responseInstance: mismatch == 2 ? "other" : "instance",
                    responseSession: mismatch == 3 ? nil : (mismatch == 6 ? "other" : "session"), now: start))
            }
            XCTAssertNil(state.challenge)
            XCTAssertThrowsError(try observe(value, in: &state))
        }
    }

    func testTransientAnswersUTF8CountAndEscapedRequestLimit() throws {
        var state = SSHAuthState(scope: try scope())
        try observe(try challenge(), in: &state)
        func validate(_ answers: [String], id: String? = nil, at time: Date? = nil) throws {
            try state.validateAnswers(answers, challengeID: id ?? self.id, currentScope: state.scope, now: time ?? start)
        }
        XCTAssertNoThrow(try validate([String(repeating: "🙂", count: 256)]))
        XCTAssertNoThrow(try validate([""]))
        XCTAssertThrowsError(try validate([String(repeating: "🙂", count: 257)]))
        XCTAssertThrowsError(try validate([]))
        XCTAssertThrowsError(try validate(["secret"], id: String(repeating: "b", count: 32)))
        XCTAssertThrowsError(try validate(["secret"], at: start.addingTimeInterval(120)))

        state = SSHAuthState(scope: try scope())
        let eight = try challenge(prompts: Array(repeating: "x", count: 8), echo: Array(repeating: false, count: 8))
        try observe(eight, in: &state)
        XCTAssertNoThrow(try validate(Array(repeating: String(repeating: "x", count: 1024), count: 8)))
        XCTAssertThrowsError(try validate(Array(repeating: String(repeating: "\u{0}", count: 1024), count: 8))) {
            XCTAssertEqual($0 as? SSHAuthError, .requestTooLarge)
        }
        XCTAssertEqual(state.challenge, eight)
    }

    func testAnswerScopeMismatchClearsStateAndRuntimeIsAlwaysDisabled() throws {
        var state = SSHAuthState(scope: try scope())
        XCTAssertThrowsError(try state.requireRuntimeSending()) {
            XCTAssertEqual($0 as? SSHAuthError, .runtimeSendingDisabled)
        }
        try observe(try challenge(), in: &state)
        XCTAssertThrowsError(try state.requireRuntimeSending())
        XCTAssertThrowsError(try state.validateAnswers(["secret"], challengeID: id, currentScope: try scope(), now: start))
        XCTAssertNil(state.challenge)
    }

    func testDebugDescriptionsRedactUntrustedContent() throws {
        let value = try challenge(prompts: ["private server prompt"])
        var state = SSHAuthState(scope: try scope())
        try observe(value, in: &state)
        for text in [String(describing: value), String(reflecting: value), String(reflecting: state)] {
            XCTAssertFalse(text.contains(id))
            XCTAssertFalse(text.contains("private server prompt"))
        }
    }

    func testExplicitRegularReadableFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("known_hosts")
        try Data("not parsed by GUI".utf8).write(to: file)
        XCTAssertNoThrow(try SSHFilePreflight.validate(knownHosts: file.path))
        XCTAssertNoThrow(try SSHFilePreflight.validate(knownHosts: file.path, identity: file.path))
        for path in ["", "relative", "~/known_hosts", "a\u{0}b"] {
            XCTAssertThrowsError(try SSHFilePreflight.validate(knownHosts: path)) {
                XCTAssertEqual($0 as? SSHFilePreflightError, .absolutePathRequired(.knownHosts))
            }
        }
        for path in [directory.path, directory.appendingPathComponent("missing").path] {
            XCTAssertThrowsError(try SSHFilePreflight.validate(knownHosts: path)) {
                XCTAssertEqual($0 as? SSHFilePreflightError, .missingOrNotRegular(.knownHosts))
            }
        }
        XCTAssertThrowsError(try SSHFilePreflight.validate(knownHosts: file.path, identity: "relative")) {
            XCTAssertEqual($0 as? SSHFilePreflightError, .absolutePathRequired(.identity))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        if !FileManager.default.isReadableFile(atPath: file.path) {
            XCTAssertThrowsError(try SSHFilePreflight.validate(knownHosts: file.path)) {
                XCTAssertEqual($0 as? SSHFilePreflightError, .notReadable(.knownHosts))
            }
        } else {
            throw XCTSkip("This account can read files with no read permission.")
        }
    }
}
