@testable import BimeronApp
import BimeronCoreCLI
import Darwin
import Foundation
import Testing

private final class NativeSelectionGateBundleMarker: NSObject {}

struct NativeSelectionGateFixture {
    let root: URL
    let executableURL: URL

    private let artifactBytes: Data
    private let artifactMode: mode_t
    private let artifactInode: ino_t

    init() async throws {
        let bundleURL = Bundle(for: NativeSelectionGateBundleMarker.self).bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        guard bundleURL.pathExtension == "xctest" else { throw FixtureError.unavailableArtifact }
        executableURL = bundleURL.deletingLastPathComponent().appending(path: "SelectionFreezeGate")
        guard Self.regularExecutable(executableURL) else { throw FixtureError.unavailableArtifact }
        var info = stat()
        guard lstat(executableURL.path, &info) == 0 else { throw FixtureError.unavailableArtifact }
        artifactBytes = try Data(contentsOf: executableURL)
        artifactMode = info.st_mode
        artifactInode = info.st_ino
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "bimeron-selection-gate-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        do {
            try Task.checkCancellation()
            try write(".selection-freeze-gate.owner", data: Data("bimeron-selection-gate-owner-v1\n".utf8))
        } catch {
            remove()
            throw error
        }
    }

    func verifyArtifactUnchanged() {
        var info = stat()
        #expect(lstat(executableURL.path, &info) == 0)
        #expect(Self.regularExecutable(executableURL))
        #expect(info.st_mode == artifactMode && info.st_ino == artifactInode)
        do { #expect(try Data(contentsOf: executableURL) == artifactBytes) }
        catch { Issue.record(error) }
    }

    func write(_ name: String, data: Data = Data()) throws {
        guard ["profile.bim", "wrong-mode.bim", ".selection-freeze-gate.owner",
               ".selection-freeze-gate.release", ".selection-freeze-gate.reject"].contains(name) else {
            throw FixtureError.unavailableArtifact
        }
        let fd = open(root.appending(path: name).path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw FixtureError.unavailableArtifact }
        defer { close(fd) }
        let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard written == data.count else { throw FixtureError.unavailableArtifact }
    }

    func input() throws -> URL {
        try write("profile.bim")
        return root.appending(path: "profile.bim")
    }

    private static func regularExecutable(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
            && FileManager.default.isExecutableFile(atPath: url.path)
    }

    enum FixtureError: Error { case unavailableArtifact, readinessTimeout }
    func sidecar(_ suffix: String) -> URL { root.appending(path: ".selection-freeze-gate." + suffix) }
    func publish(_ suffix: String) throws {
        guard ["release", "reject"].contains(suffix) else { throw FixtureError.unavailableArtifact }
        try write(".selection-freeze-gate." + suffix)
    }
    func remove() {
        var info = stat()
        guard root.lastPathComponent.hasPrefix("bimeron-selection-gate-"),
              UUID(uuidString: String(root.lastPathComponent.dropFirst("bimeron-selection-gate-".count))) != nil,
              lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o7777 == 0o700 else { return }
        try? FileManager.default.removeItem(at: root)
    }

    func waitUntilStarted() async throws {
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: sidecar("started").path) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw FixtureError.readinessTimeout
    }
}

@Test func nativeSelectionGateMetadataAndInvalidArguments() async throws {
    let fixture = try await NativeSelectionGateFixture()
    defer { fixture.verifyArtifactUnchanged(); fixture.remove() }
    let attributes = try FileManager.default.attributesOfItem(atPath: fixture.executableURL.path)
    #expect(attributes[.type] as? FileAttributeType == .typeRegular)
    #expect(FileManager.default.isExecutableFile(atPath: fixture.executableURL.path))
    #expect(fixture.executableURL.deletingLastPathComponent() != fixture.root)
    #expect(!fixture.executableURL.path.contains(".app/"))
    for (url, kind, mode) in [(fixture.root, mode_t(S_IFDIR), mode_t(0o700)),
                               (fixture.sidecar("owner"), mode_t(S_IFREG), mode_t(0o600))] {
        var info = stat()
        #expect(lstat(url.path, &info) == 0)
        #expect(info.st_mode & S_IFMT == kind && info.st_mode & 0o7777 == mode)
        #expect(info.st_uid == getuid())
    }
    let cli = CoreCLI(executableURL: fixture.executableURL, timeout: .seconds(2))
    let version = try await cli.version()
    #expect(version.version == "future-unknown" && !version.modified)
    #expect(version.goVersion == "unknown" && version.platform == "darwin" && version.architecture == "unknown")
    #expect(version.revision == nil && version.commitTime == nil)
    let capabilities = try await cli.capabilities()
    #expect(capabilities.platform == "darwin")
    #expect(!capabilities.vpn && !capabilities.proxy && !capabilities.ipv4 && !capabilities.ipv6)
    #expect(!capabilities.ipSplit && !capabilities.domainSplit && !capabilities.appSplit)
    #expect(!capabilities.killSwitch && !capabilities.daemon)
    let ike = capabilities.ikev2
    #expect(!ike.administratorRequired && !ike.supported && !ike.foregroundOnly && !ike.preconfiguredProfile)
    #expect(!ike.proxy && !ike.ipSplit && !ike.domainSplit && !ike.killSwitch && !ike.dnsProtection && !ike.stats)
    let foreign = try await NativeSelectionGateFixture()
    let missingOwner = try await NativeSelectionGateFixture()
    let malformed = try await NativeSelectionGateFixture()
    defer { foreign.remove(); missingOwner.remove(); malformed.remove() }
    let foreignDirectory = foreign.root.appending(path: "foreign")
    try FileManager.default.createDirectory(at: foreignDirectory, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    let nestedRoot = foreign.root.appending(path: "bimeron-selection-gate-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: nestedRoot, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    let nestedInput = nestedRoot.appending(path: "profile.bim")
    for (url, data) in [(nestedInput, Data()),
                        (nestedRoot.appending(path: ".selection-freeze-gate.owner"), Data("bimeron-selection-gate-owner-v1\n".utf8))] {
        try #require(FileManager.default.createFile(atPath: url.path, contents: data,
                                                    attributes: [.posixPermissions: 0o600]))
    }
    let outsideInput = foreignDirectory.appending(path: "profile.bim")
    try Data().write(to: outsideInput)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outsideInput.path)
    let missingInput = try missingOwner.input()
    try FileManager.default.removeItem(at: missingOwner.sidecar("owner"))
    let malformedInput = try malformed.input()
    try FileManager.default.removeItem(at: malformed.sidecar("owner"))
    try malformed.write(".selection-freeze-gate.owner", data: Data("malformed".utf8))
    let validInput = try fixture.input()
    let symlinkInput = fixture.root.appending(path: "link.bim")
    try FileManager.default.createSymbolicLink(at: symlinkInput, withDestinationURL: validInput)
    let wrongModeInput = fixture.root.appending(path: "wrong-mode.bim")
    try fixture.write("wrong-mode.bim")
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: wrongModeInput.path)
    // Only this known native executable is launched directly to test unsupported argv.
    for (caseIndex, arguments) in [[], ["unknown"], ["version", "extra"], ["capabilities", "extra"], ["validate"],
                      ["validate", fixture.root.path], ["validate", fixture.root.appending(path: "missing").path],
                      ["validate", fixture.root.path, "extra"],
                      ["validate", outsideInput.path], ["validate", nestedInput.path], ["validate", missingInput.path],
                      ["validate", malformedInput.path], ["validate", symlinkInput.path],
                      ["validate", wrongModeInput.path],
                      ["validate", fixture.root.path + "/../" + fixture.root.lastPathComponent + "/profile.bim"]].enumerated() {
        let process = Process()
        process.executableURL = fixture.executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let pid = process.processIdentifier
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while process.isRunning && ContinuousClock.now < deadline {
            await Task.detached { try? await Task.sleep(for: .milliseconds(5)) }.value
        }
        let timedOut = process.isRunning
        if timedOut {
            if process.isRunning { _ = Darwin.kill(pid, SIGKILL) }
            let cleanupDeadline = ContinuousClock.now.advanced(by: .seconds(1))
            while process.isRunning && ContinuousClock.now < cleanupDeadline {
                await Task.detached { try? await Task.sleep(for: .milliseconds(5)) }.value
            }
        }
        try #require(!process.isRunning, "Invalid-argument case \(caseIndex) cleanup timed out")
        #expect(Darwin.kill(pid, 0) == -1 && errno == ESRCH)
        var childStatus: Int32 = 0
        #expect(waitpid(pid, &childStatus, WNOHANG) == -1 && errno == ECHILD)
        try #require(!timedOut, "Invalid-argument case \(caseIndex) timed out")
        #expect(process.terminationReason == .exit)
        #expect(process.terminationStatus == 9)
    }
    for root in [fixture.root, foreign.root, foreignDirectory, nestedRoot, missingOwner.root, malformed.root] {
        for suffix in ["started", "release", "reject"] {
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".selection-freeze-gate." + suffix).path))
        }
    }
}

@Test(arguments: [false, true]) @MainActor func nativeSelectionGatePostSelectionWaitsForReleaseAndRejects(reject: Bool) async throws {
    let fixture = try await NativeSelectionGateFixture()
    defer { fixture.verifyArtifactUnchanged(); fixture.remove() }
    let cli = CoreCLI(executableURL: fixture.executableURL, timeout: .seconds(2))
    // POST-SELECTION validation follows the real metadata probe; this is not cold-start readiness.
    try await SessionCoreSelection.probe(cli)
    #expect(!FileManager.default.fileExists(atPath: fixture.sidecar("started").path))
    let input = try fixture.input()
    if reject { try fixture.publish("reject") }
    var finished = false
    let task = Task {
        defer { finished = true }
        return try await cli.validate(fileURL: input)
    }
    do {
        try await fixture.waitUntilStarted()
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.sidecar("started").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(!finished)
        try await Task.sleep(for: .milliseconds(30))
        #expect(!finished)
        try fixture.publish("release")
        do {
            let output = try await task.value
            #expect(!reject)
            #expect(output.stderr.isEmpty && !output.stdoutTruncated)
            let pid = try #require(Int32(String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
            #expect(Darwin.kill(pid, 0) == -1 && errno == ESRCH)
        } catch CoreCLIError.exit(let status, let output) {
            #expect(reject && status == 7 && output.stderr.isEmpty)
            let pid = try #require(Int32(String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
            #expect(pid > 0)
            #expect(Darwin.kill(pid, 0) == -1 && errno == ESRCH)
            var childStatus: Int32 = 0
            #expect(waitpid(pid, &childStatus, WNOHANG) == -1 && errno == ECHILD)
        }
    } catch {
        task.cancel()
        _ = await task.result
        throw error
    }
}

@Test func nativeSelectionGatePostSelectionCancellationKillsAndReapsBeforeCleanup() async throws {
    let fixture = try await NativeSelectionGateFixture()
    defer { fixture.verifyArtifactUnchanged(); fixture.remove() }
    let cli = CoreCLI(executableURL: fixture.executableURL, timeout: .seconds(2))
    // POST-SELECTION validation follows the real metadata probe; this is not cold-start readiness.
    try await SessionCoreSelection.probe(cli)
    #expect(!FileManager.default.fileExists(atPath: fixture.sidecar("started").path))
    let input = try fixture.input()
    let task = Task { try await cli.validate(fileURL: input) }
    do { try await fixture.waitUntilStarted() }
    catch { task.cancel(); _ = await task.result; throw error }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Expected native validation cancellation")
    } catch CoreCLIError.cancelled(let output) {
        let pid = try #require(Int32(String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(pid > 0)
        #expect(Darwin.kill(pid, 0) == -1 && errno == ESRCH)
        var status: Int32 = 0
        #expect(waitpid(pid, &status, WNOHANG) == -1 && errno == ECHILD)
        #expect(FileManager.default.fileExists(atPath: fixture.executableURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.sidecar("release").path))
    }
}

@Test @MainActor func nativeSelectionGateConcurrentDataRootsAreIsolated() async throws {
    let first = try await NativeSelectionGateFixture()
    defer { first.verifyArtifactUnchanged(); first.remove() }
    let second = try await NativeSelectionGateFixture()
    defer { second.verifyArtifactUnchanged(); second.remove() }
    #expect(first.root != second.root)
    #expect(first.executableURL == second.executableURL)
    let firstCLI = CoreCLI(executableURL: first.executableURL, timeout: .seconds(2))
    let secondCLI = CoreCLI(executableURL: second.executableURL, timeout: .seconds(2))
    try await SessionCoreSelection.probe(firstCLI)
    try await SessionCoreSelection.probe(secondCLI)
    let firstInput = try first.input()
    let secondInput = try second.input()
    var secondFinished = false
    let firstTask = Task { try await firstCLI.validate(fileURL: firstInput) }
    let secondTask = Task {
        defer { secondFinished = true }
        return try await secondCLI.validate(fileURL: secondInput)
    }
    do {
        try await first.waitUntilStarted()
        try await second.waitUntilStarted()
        try first.publish("release")
        _ = try await firstTask.value
        #expect(!secondFinished)
        #expect(!FileManager.default.fileExists(atPath: second.sidecar("release").path))
        try second.publish("reject")
        try second.publish("release")
        do {
            _ = try await secondTask.value
            Issue.record("Expected isolated rejection")
        } catch CoreCLIError.exit(let status, _) { #expect(status == 7) }
    } catch {
        firstTask.cancel()
        secondTask.cancel()
        _ = await firstTask.result
        _ = await secondTask.result
        throw error
    }
}
