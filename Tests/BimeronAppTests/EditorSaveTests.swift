import Foundation
import Testing
import BimeronModel
@testable import BimeronCoreCLI
@testable import BimeronApp

@Test @MainActor func editorSaveUsesProtectedExactBytesAndPreservesFailures() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appending(path: "profiles")
    let library = ProfileLibrary(directory: directory)
    let text = "\u{feff}[Profile]\r\nVersion = 1\r\nName = Original\r\n[AccessKey]\r\nSOCKS5 = socks5://localhost:1080"
    let original = try await library.add(ConfigDocument(text))
    let destination = directory.appending(path: original.id.uuidString + ".conf")
    var draft = original
    draft.document.set("Profile", "Name", "Draft")
    let expected = root.appending(path: "expected")
    let captured = root.appending(path: "captured")
    let executable = root.appending(path: "fake-core")
    func cli(_ body: String, timeout: Duration = .seconds(2)) throws -> CoreCLI {
        try Data(("#!/bin/sh\n" + body).utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return CoreCLI(testShellScript: executable, timeout: timeout)
    }
    let suite = "EditorSaveTests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("en", forKey: "language")
    let stage = root.appending(path: "stage")
    let evidence = EditorSaveEvidence(stage: stage)
    let success = try cli("""
    test "$1" = validate || exit 1
    printf dirname > '\(stage.path)'
    test "$(dirname "$2")" = '\(directory.path)' || exit 2
    printf stat > '\(stage.path)'
    test "$(stat -f %Lp "$2")" = 600 || exit 3
    printf cmp > '\(stage.path)'
    cmp "$2" '\(expected.path)' || exit 4
    printf cp > '\(stage.path)'
    cp "$2" '\(captured.path)' || exit 5
    printf done > '\(stage.path)'
    """)
    var observedSuccess = success
    observedSuccess.observer = { evidence.record($0) }
    var model = AppModel(library: library, coreCLI: observedSuccess, defaults: defaults)
    // No-op, BOM, CRLF and missing final newline pass through the actual model path.
    try Data(text.utf8).write(to: expected)
    let saved = await model.save(original, original: original)
    print(evidence.finish())
    try #require(saved,
                 "No-op save failed:\n\(model.diagnosticSnapshot().text(includeFreeText: false))")
    #expect(try Data(contentsOf: destination) == Data(text.utf8))
    _ = try cli("""
    test "$1" = validate || exit 1
    test "$(dirname "$2")" = '\(directory.path)' || exit 2
    test "$(stat -f %Lp "$2")" = 600 || exit 3
    cmp "$2" '\(expected.path)' || exit 4
    cp "$2" '\(captured.path)'
    """)
    model = AppModel(library: library, coreCLI: success, defaults: defaults)
    try Data(draft.document.text.utf8).write(to: expected)
    try #require(await model.save(draft, original: original),
                 "Draft save failed:\n\(model.diagnosticSnapshot().text(includeFreeText: false))")
    #expect(try Data(contentsOf: destination) == Data(contentsOf: captured))
    #expect((try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)

    for mode in ["reject", "missing", "timeout", "cancel", "stale"] {
        let core: CoreCLI?
        switch mode {
        case "reject": core = try cli("echo password-secret; echo credentials-secret >&2; exit 1")
        case "missing": core = CoreCLI(executableURL: root.appending(path: "absent"))
        case "timeout": core = try cli("exec /bin/sleep 2", timeout: .milliseconds(80))
        case "cancel": core = try cli("exec /bin/sleep 2")
        default: core = try cli("exit 0")
        }
        let failing = AppModel(library: library, coreCLI: core, defaults: defaults)
        var pending = draft
        pending.document.set("Profile", "Name", "Unsaved value")
        let snapshot = pending
        let task = Task { await failing.save(snapshot, original: original) }
        if mode == "cancel" {
            try await Task.sleep(for: .milliseconds(30))
            task.cancel()
        }
        #expect(await task.value == false)
        #expect(pending == snapshot)
        #expect(try Data(contentsOf: destination) == Data(draft.document.text.utf8))
        #expect(!(failing.alertMessage ?? "").contains("secret"))
        #expect(failing.log.allSatisfy { !$0.message.contains("secret") })
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasSuffix(".tmp") })
    }
    let unavailable = AppModel(library: library, coreCLI: nil, defaults: defaults)
    #expect(await unavailable.save(draft, original: draft) == false)
}

@Test func concurrentEditorReplacementRejectsStaleOriginal() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let original = try await library.add(ConfigDocument.new(name: "Original", key: "ss://example"))
    var changed = original
    changed.document.set("Profile", "Name", "Concurrent")
    let replacement = changed
    await #expect(throws: EditorSaveError.self) {
        try await library.update(original, expectedOriginal: Data(original.document.text.utf8)) { _ in
            try await library.update(replacement)
        }
    }
    #expect(try await library.load().profiles == [replacement])
}

@Test func cancellationImmediatelyBeforeCommitKeepsOriginal() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let original = try await library.add(ConfigDocument.new(name: "Original", key: "ss://example"))
    var draft = original
    draft.document.set("Profile", "Name", "Cancelled")
    let snapshot = draft
    let task = Task {
        try await library.update(snapshot, expectedOriginal: Data(original.document.text.utf8)) { _ in
            // A successful validator must not bypass the final cancellation gate.
            withUnsafeCurrentTask { $0?.cancel() }
        }
    }
    do {
        try await task.value
        Issue.record("Cancelled save committed")
    } catch is CancellationError {} catch { throw error }
    #expect(try await library.load().profiles == [original])
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasSuffix(".tmp") })
}

@Test func validatorRewritingStagedBytesKeepsOriginalAndCleansUp() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let original = try await library.add(ConfigDocument.new(name: "Original", key: "ss://example"))
    let destination = root.appending(path: original.id.uuidString + ".conf")
    let originalBytes = try Data(contentsOf: destination)
    let originalEntries = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    var draft = original
    draft.document.set("Profile", "Name", "Draft")

    do {
        try await library.update(draft, expectedOriginal: originalBytes) { staged in
            try Data("Validator rewrote the document".utf8).write(to: staged)
        }
        Issue.record("Save accepted rewritten staged bytes")
    } catch EditorSaveError.changedStaging {} catch { throw error }

    #expect(try Data(contentsOf: destination) == originalBytes)
    #expect(try await library.load().profiles == [original])
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == originalEntries)
}

@Test func stagedReadFailureKeepsOriginalAndCleansUp() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let original = try await library.add(ConfigDocument.new(name: "Original", key: "ss://example"))
    let destination = root.appending(path: original.id.uuidString + ".conf")
    let originalBytes = try Data(contentsOf: destination)
    let originalEntries = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    var draft = original
    draft.document.set("Profile", "Name", "Draft")

    // shortcut: this covers staged reread failure, not rename failure; a deterministic rename test needs a filesystem hook.
    // Replacing either path with a directory fails its reread before rename and cannot exercise the final commit.
    await #expect(throws: ProfileError.tooLarge) {
        try await library.update(draft, expectedOriginal: originalBytes) { staged in
            try Data(repeating: 0x61, count: ConfigDocument.sizeLimit + 1).write(to: staged)
        }
    }

    #expect(try Data(contentsOf: destination) == originalBytes)
    #expect(try await library.load().profiles == [original])
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == originalEntries)
}

@Test func editorShellFixturePreservesLiteralArguments() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appending(path: "fixture ' \"$dollar\"; echo injected; #")
    let input = root.appending(path: "input ' \"$dollar\"; echo injected; #")
    let bytes = Data("unchanged input".utf8)
    try bytes.write(to: input)
    try Data("printf '%s\\n' \"$0\" \"$#\" \"$1\" \"$2\"\n".utf8).write(to: script)
    let output = try await CoreCLI(testShellScript: script, timeout: .seconds(2)).validate(fileURL: input)
    #expect(output.stdout == Data("\(script.path)\n2\nvalidate\n\(input.path)\n".utf8))
    #expect(output.stderr.isEmpty)
    #expect(try Data(contentsOf: input) == bytes)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == [script.lastPathComponent, input.lastPathComponent].sorted())
}

@Test func editorShellFixtureMatchesPublicExecutableArguments() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appending(path: "echo-fixture")
    let input = root.appending(path: "input with spaces")
    try Data("exec /bin/echo \"$@\"\n".utf8).write(to: script)
    let fixture = try await CoreCLI(testShellScript: script, timeout: .seconds(2)).validate(fileURL: input)
    let normal = try await CoreCLI(executableURL: URL(fileURLWithPath: "/bin/echo"), timeout: .seconds(2)).validate(fileURL: input)
    #expect(normal.stdout == Data("validate \(input.path)\n".utf8))
    #expect(fixture.stdout == normal.stdout)
    #expect(fixture.stderr == normal.stderr)
    #expect(!normal.stdoutTruncated && !normal.stderrTruncated)
    #expect(!fixture.stdoutTruncated && !fixture.stderrTruncated)
}

@Test(arguments: ["timeout", "cancel", "reject"])
func editorShellFixturePreservesTypedFailures(mode: String) async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appending(path: "failure-fixture")
    let input = root.appending(path: "input")
    let marker = root.appending(path: "launched")
    let bytes = Data("persisted input".utf8)
    try bytes.write(to: input)
    // A pre-cancelled invocation must never reach even the script's first write.
    let body = mode == "reject" ? "exit 7" : "exec /bin/sleep 2"
    try Data("printf launched > '\(marker.path)'\n\(body)\n".utf8).write(to: script)
    let core = CoreCLI(testShellScript: script, timeout: .milliseconds(80))
    let task = Task {
        if mode == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
        return try await core.validate(fileURL: input)
    }
    do {
        _ = try await task.value
        Issue.record("Expected \(mode) failure")
    } catch let error as CoreCLIError {
        switch (mode, error) {
        case ("timeout", .timedOut), ("cancel", .cancelled): break
        case ("reject", .exit(let status, _)): #expect(status == 7)
        default: Issue.record("Unexpected typed outcome: \(error)")
        }
    }
    #expect(FileManager.default.fileExists(atPath: marker.path) == (mode != "cancel"))
    #expect(try Data(contentsOf: input) == bytes)
}
