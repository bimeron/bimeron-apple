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
    @Test("B-VERSION-SUPPORTED: source-derived Core build schema")
    func versionContract() async throws {
        let fixture = try Fixture("""
        test "$#" = 1 && test "$1" = version || exit 9
        echo '\(CoreParserSamples.version)'
        """)
        defer { fixture.cleanup() }
        let info = try await fixture.client().version()
        #expect(info.version == "0.3.0-beta.2")
        #expect(info.goVersion == "go1.24")
        #expect(info.revision == nil && info.commitTime == nil)
        #expect(!info.modified && info.platform == "darwin" && info.architecture == "arm64")
        try fixture.unchanged()
    }

    @Test("B-VERSION-UNSUPPORTED: unknown version decodes; compatibility policy pending")
    func unknownVersionDecodes() async throws {
        let sample = CoreParserSamples.version.replacingOccurrences(of: "0.3.0-beta.2", with: "0.0.0")
        let fixture = try Fixture("echo '\(sample)'")
        defer { fixture.cleanup() }
        #expect(try await fixture.client().version().version == "0.0.0")
        try fixture.unchanged()
    }

    @Test("B-CAPABILITIES-SUPPORTED: source-derived macOS declarations")
    func capabilitiesContract() async throws {
        let fixture = try Fixture("""
        test "$#" = 1 && test "$1" = capabilities || exit 9
        echo '\(CoreParserSamples.macOSCapabilities)'
        """)
        defer { fixture.cleanup() }
        let capabilities = try await fixture.client().capabilities()
        #expect(capabilities.platform == "darwin")
        #expect(capabilities.vpn && capabilities.proxy && capabilities.ipv4 && capabilities.ipv6)
        #expect(capabilities.ipSplit && capabilities.domainSplit && capabilities.daemon)
        #expect(!capabilities.appSplit && !capabilities.killSwitch)
        expectNoIKEv2Support(capabilities.ikev2)
        try fixture.unchanged()
    }

    @Test("B-CAPABILITIES-UNSUPPORTED: all false flags decode without changing config")
    func unsupportedCapabilitiesDecode() async throws {
        let sample = CoreParserSamples.macOSCapabilities.replacingOccurrences(of: "true", with: "false")
        let fixture = try Fixture("echo '\(sample)'")
        defer { fixture.cleanup() }
        let capabilities = try await fixture.client().capabilities()
        #expect(!capabilities.vpn && !capabilities.proxy && !capabilities.ipv4 && !capabilities.ipv6)
        #expect(!capabilities.ipSplit && !capabilities.domainSplit && !capabilities.daemon)
        #expect(!capabilities.appSplit && !capabilities.killSwitch)
        expectNoIKEv2Support(capabilities.ikev2)
        try fixture.unchanged()
    }

    private func expectNoIKEv2Support(_ capabilities: CLIPlatformCapabilities.IKEv2) {
        #expect(!capabilities.administratorRequired && !capabilities.supported)
        #expect(!capabilities.foregroundOnly && !capabilities.preconfiguredProfile)
        #expect(!capabilities.proxy && !capabilities.ipSplit && !capabilities.domainSplit)
        #expect(!capabilities.killSwitch && !capabilities.dnsProtection && !capabilities.stats)
    }

    @Test("B-VERSION-MALFORMED / B-CAPABILITIES-MALFORMED: missing required fields",
          arguments: ["version", "capabilities"])
    func missingFieldsRejected(command: String) async throws {
        let sample = command == "version"
            ? CoreParserSamples.version.replacingOccurrences(of: "\"modified\":false,", with: "")
            : CoreParserSamples.macOSCapabilities.replacingOccurrences(of: "\"supported\":false,", with: "")
        let fixture = try Fixture("echo '\(sample)'")
        defer { fixture.cleanup() }
        do {
            if command == "version" { _ = try await fixture.client().version() }
            else { _ = try await fixture.client().capabilities() }
            Issue.record("Expected missing-field decode failure")
        } catch CoreCLIError.decode(let actual, _, _) {
            #expect(actual == command)
        }
        try fixture.unchanged()
    }

    @Test("B-VERSION-MALFORMED / B-CAPABILITIES-MALFORMED: invalid JSON", arguments: ["version", "capabilities"])
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

    @Test("B-VALIDATE-VALID") func validationPreservesArgumentAndFile() async throws {
        let fixture = try Fixture("""
        test "$#" = 2 && test "$1" = validate || exit 9
        printf '%s' "$2"
        """)
        defer { fixture.cleanup() }
        let output = try await fixture.client().validate(fileURL: fixture.input)
        #expect(String(decoding: output.stdout, as: UTF8.self) == fixture.input.path)
        try fixture.unchanged()
    }

    @Test("B-NONZERO-STDERR") func nonzeroPreservesDiagnosticsAndInput() async throws {
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

    @Test("B-VALIDATE-INVALID: exit one preserves editable input")
    func invalidValidationPreservesInput() async throws {
        let fixture = try Fixture("echo 'error: invalid config' >&2; exit 1")
        defer { fixture.cleanup() }
        do {
            _ = try await fixture.client().validate(fileURL: fixture.input)
            Issue.record("Expected validation failure")
        } catch CoreCLIError.exit(let status, let output) {
            #expect(status == 1)
            #expect(output.diagnosticText.contains("invalid config"))
        }
        try fixture.unchanged()
    }

    @Test("B-MISSING") func missingExecutable() async throws {
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

    @Test("B-TRUNCATED") func truncatedJSONIsRejected() async throws {
        let fixture = try Fixture("echo '{\"version\":\"long\"}'")
        defer { fixture.cleanup() }
        do {
            _ = try await fixture.client(limit: 2).version()
            Issue.record("Expected decode failure")
        } catch CoreCLIError.decode(_, _, let output) {
            #expect(output.stdoutTruncated)
        }
    }

    @Test("B-TIMEOUT / B-CANCEL: resistant process is reaped", arguments: [false, true])
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

    @Test("B-CANCEL") func cancellationBeforeLaunch() async throws {
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
