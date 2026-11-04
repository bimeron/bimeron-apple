import Foundation
import Testing
import Darwin
import BimeronCoreCLI

private struct Fixture {
    let directory: URL
    let executable: URL
    let input: URL
    let original = Data("[Profile]\nName = unchanged\n".utf8)

    init(_ body: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "BimeronCoreCLITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appending(path: "fixture core")
        input = directory.appending(path: "draft ; $(touch injected) ' config.conf")
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try original.write(to: input)
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
    func unchanged() throws { #expect(try Data(contentsOf: input) == original) }
    func client(timeout: Duration = .seconds(3), limit: Int = 1_048_576) -> CoreCLI {
        CoreCLI(executableURL: executable, timeout: timeout, outputLimit: limit)
    }
}

@Suite(.serialized)
struct CoreCLITests {
    @Test func versionContract() async throws {
        let fixture = try Fixture("""
        test "$#" = 1 && test "$1" = version || exit 9
        echo '{"version":"0.3.0-beta.2","modified":false,"go_version":"go1.24","platform":"darwin","architecture":"arm64"}'
        """)
        defer { fixture.cleanup() }
        let info = try await fixture.client().version()
        #expect(info.version == "0.3.0-beta.2")
        #expect(info.goVersion == "go1.24")
        #expect(info.revision == nil && info.commitTime == nil)
    }

    @Test func capabilitiesContract() async throws {
        let fixture = try Fixture("""
        test "$#" = 1 && test "$1" = capabilities || exit 9
        echo '{"platform":"darwin","vpn":true,"proxy":true,"ipv4":true,"ipv6":true,"ip_split":true,"domain_split":true,"app_split":false,"kill_switch":false,"daemon":true,"ikev2":{"administrator_required":true,"supported":true,"foreground_only":true,"preconfigured_profile":true,"proxy":false,"ip_split":false,"domain_split":false,"kill_switch":false,"dns_protection":false,"stats":false}}'
        """)
        defer { fixture.cleanup() }
        let capabilities = try await fixture.client().capabilities()
        #expect(capabilities.platform == "darwin")
        #expect(!capabilities.killSwitch && capabilities.ikev2.administratorRequired)
    }

    @Test(arguments: ["version", "capabilities"])
    func malformedJSON(command: String) async throws {
        let fixture = try Fixture("echo broken; echo diagnostic >&2")
        defer { fixture.cleanup() }
        do {
            if command == "version" { _ = try await fixture.client().version() }
            else { _ = try await fixture.client().capabilities() }
            Issue.record("Expected decode failure")
        } catch CoreCLIError.decode(let actual, _, let output) {
            #expect(actual == command)
            #expect(output.stdout == Data("broken\n".utf8))
            #expect(output.diagnosticText.contains("diagnostic"))
        }
        try fixture.unchanged()
    }

    @Test func validationPreservesArgumentAndFile() async throws {
        let fixture = try Fixture("""
        test "$#" = 2 && test "$1" = validate || exit 9
        printf '%s' "$2"
        """)
        defer { fixture.cleanup() }
        let output = try await fixture.client().validate(fileURL: fixture.input)
        #expect(String(decoding: output.stdout, as: UTF8.self) == fixture.input.path)
        try fixture.unchanged()
    }

    @Test func nonzeroPreservesDiagnosticsAndInput() async throws {
        let fixture = try Fixture("echo partial; echo 'error: invalid config' >&2; exit 7")
        defer { fixture.cleanup() }
        do {
            _ = try await fixture.client().validate(fileURL: fixture.input)
            Issue.record("Expected exit failure")
        } catch CoreCLIError.exit(let status, let output) {
            #expect(status == 7)
            #expect(output.stdout == Data("partial\n".utf8))
            #expect(output.diagnosticText.contains("invalid config"))
        }
        try fixture.unchanged()
    }

    @Test func missingExecutable() async throws {
        let fixture = try Fixture("exit 0")
        defer { fixture.cleanup() }
        let missing = fixture.directory.appending(path: "missing")
        do {
            _ = try await CoreCLI(executableURL: missing).validate(fileURL: fixture.input)
            Issue.record("Expected launch failure")
        } catch CoreCLIError.launch(let url, let message) {
            #expect(url == missing && !message.isEmpty)
        }
        try fixture.unchanged()
    }

    @Test(arguments: [1024, 1_048_576])
    func concurrentOutputIsDrainedAndBounded(limit: Int) async throws {
        let fixture = try Fixture("""
        /usr/bin/head -c 524288 /dev/zero &
        /usr/bin/head -c 524288 /dev/zero >&2 &
        wait
        """)
        defer { fixture.cleanup() }
        let output = try await fixture.client(limit: limit).validate(fileURL: fixture.input)
        #expect(output.stdout.count == min(limit, 524288))
        #expect(output.stderr.count == min(limit, 524288))
        #expect(output.stdoutTruncated == (limit < 524288))
        #expect(output.stderrTruncated == (limit < 524288))
    }

    @Test func truncatedJSONIsRejected() async throws {
        let fixture = try Fixture("echo '{\"version\":\"long\"}'")
        defer { fixture.cleanup() }
        do {
            _ = try await fixture.client(limit: 2).version()
            Issue.record("Expected decode failure")
        } catch CoreCLIError.decode(_, _, let output) {
            #expect(output.stdoutTruncated)
        }
    }

    @Test(arguments: [false, true])
    func timeoutAndCancellationKillResistantProcess(cancel: Bool) async throws {
        let fixture = try Fixture("trap '' TERM; echo $$ >&2; echo ready >&2; while :; do :; done")
        defer { fixture.cleanup() }
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task { try await fixture.client(timeout: .seconds(1)).validate(fileURL: fixture.input) }
        if cancel {
            try await Task.sleep(for: .milliseconds(700))
            task.cancel()
        }
        do {
            _ = try await task.value
            Issue.record("Expected interrupted process")
        } catch CoreCLIError.cancelled(let output) {
            #expect(cancel && output.diagnosticText.contains("ready"))
            try expectProcessGone(output)
        } catch CoreCLIError.timedOut(let output) {
            #expect(!cancel && output.diagnosticText.contains("ready"))
            try expectProcessGone(output)
        }
        #expect(start.duration(to: clock.now) < .seconds(4))
        try fixture.unchanged()
    }

    private func expectProcessGone(_ output: CLIOutput) throws {
        let pid = try #require(Int32(output.diagnosticText.split(separator: "\n").first.map(String.init) ?? ""))
        #expect(Darwin.kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test func cancellationBeforeLaunch() async throws {
        let fixture = try Fixture("echo launched > \"$2\"")
        defer { fixture.cleanup() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fixture.client().validate(fileURL: fixture.input)
        }
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch CoreCLIError.cancelled { }
        try fixture.unchanged()
    }
}
