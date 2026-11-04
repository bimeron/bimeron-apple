import BimeronCoreCLI
import BimeronModel
import Foundation
import Testing
@testable import BimeronApp

private let selectionVersion = #"{"version":"future-unknown","modified":false,"go_version":"unknown","platform":"darwin","architecture":"unknown"}"#
private let selectionCapabilities = #"{"platform":"darwin","vpn":false,"proxy":false,"ipv4":false,"ipv6":false,"ip_split":false,"domain_split":false,"app_split":false,"kill_switch":false,"daemon":false,"ikev2":{"administrator_required":false,"supported":false,"foreground_only":false,"preconfigured_profile":false,"proxy":false,"ip_split":false,"domain_split":false,"kill_switch":false,"dns_protection":false,"stats":false}}"#

private struct SelectionFixture {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func executable(version: String = selectionVersion, capabilities: String = selectionCapabilities,
                    delay: Bool = false, validation: Int = 0, executable: Bool = true, gateValidation: Bool = false, gateCapabilities: Bool = false) throws -> URL {
        let url = root.appending(path: UUID().uuidString)
        let script = """
        #!/bin/sh
        case "$1" in
        version)
        \(delay ? "exec /bin/sleep 30" : "")
        cat <<'VERSION'
        \(version)
        VERSION
        ;;
        capabilities)
        \(gateCapabilities ? "touch \"$0.capabilities-started\"; while ! test -f \"$0.capabilities-release\"; do /bin/sleep 0.01; done" : "")
        cat <<'CAPABILITIES'
        \(capabilities)
        CAPABILITIES
        ;;
        validate) test -f "$2" || exit 9
        \(gateValidation ? "touch \"$0.started\"; while ! test -f \"$0.release\"; do /bin/sleep 0.01; done" : "")
        exit \(validation);;
        *) exit 8;;
        esac
        """
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o700 : 0o600], ofItemAtPath: url.path)
        return url
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Test @MainActor func selectedCoreUsesActualCreateAndSaveAndResetRestoresInjectedCLI() async throws {
    let fixture = try SelectionFixture()
    defer { fixture.remove() }
    let settings = try IsolatedAppSettings()
    let rejecting = try fixture.executable(validation: 1)
    let selected = try fixture.executable()
    let model = AppModel(library: ProfileLibrary(directory: fixture.root.appending(path: "profiles")),
                         coreCLI: CoreCLI(executableURL: rejecting), defaults: settings.defaults)
    let draft = try EditorProtocol.socks5.document(name: "Draft", values: ["Server": "localhost", "Port": "1080"])
    #expect(await model.create(draft) == false)
    model.selectCoreExecutable(selected)
    await model.waitForCoreProbe()
    #expect(model.coreSelection.statusKey.contains("UNTRUSTED"))
    #expect(await model.create(draft))
    let original = try #require(model.selected)
    var changed = original
    changed.document.set("Profile", "Name", "Changed")
    #expect(await model.save(changed, original: original))
    #expect(model.selected?.document.name == "Changed")
    model.resetCoreExecutable()
    #expect(await model.create(draft) == false)
    #expect(!model.log.description.contains(fixture.root.path))
}

@Test @MainActor func failedSelectionsBlockWithoutFallbackAndRedactOutput() async throws {
    let fixture = try SelectionFixture()
    defer { fixture.remove() }
    let settings = try IsolatedAppSettings()
    let baseline = try fixture.executable()
    let model = AppModel(library: ProfileLibrary(directory: fixture.root.appending(path: "profiles")),
                         coreCLI: CoreCLI(executableURL: baseline), defaults: settings.defaults)
    let draft = try EditorProtocol.socks5.document(name: "Draft", values: ["Server": "localhost", "Port": "1080"])
    #expect(await model.create(draft))
    let original = try #require(model.selected)
    var edited = original
    edited.document.set("Profile", "Name", "Uncommitted")
    let invalid = [
        try fixture.executable(version: "private-output-secret"),
        try fixture.executable(version: selectionVersion.replacingOccurrences(of: "future-unknown", with: "   ")),
        try fixture.executable(version: selectionVersion.replacingOccurrences(of: "darwin", with: "linux")),
        try fixture.executable(capabilities: selectionCapabilities.replacingOccurrences(of: "darwin", with: "linux")),
        try fixture.executable(capabilities: #"{"platform":"darwin"}"#),
        try fixture.executable(capabilities: selectionCapabilities.replacingOccurrences(of: #","stats":false"#, with: "")),
        try fixture.executable(executable: false), fixture.root, fixture.root.appending(path: "missing")
    ]
    for candidate in invalid {
        model.selectCoreExecutable(candidate)
        await model.waitForCoreProbe()
        #expect(model.coreSelection.statusKey.contains("failed"))
        #expect(await model.create(draft) == false)
        #expect(await model.save(edited, original: original) == false)
        #expect(try await model.library.load().profiles == [original])
        #expect(edited.document.name == "Uncommitted")
    }
    #expect(!model.log.description.contains("private-output-secret"))
    #expect(!(model.alertMessage ?? "").contains(fixture.root.path))
    model.resetCoreExecutable()
    #expect(await model.create(draft))
}

@Test @MainActor func pendingCapabilitiesAndTimeoutOrCancellationBlockWithoutFallback() async throws {
    let fixture = try SelectionFixture()
    defer { fixture.remove() }
    let settings = try IsolatedAppSettings()
    let baseline = try fixture.executable()
    let model = AppModel(library: ProfileLibrary(directory: fixture.root.appending(path: "profiles")),
                         coreCLI: CoreCLI(executableURL: baseline), defaults: settings.defaults)
    let draft = try EditorProtocol.socks5.document(name: "Draft", values: ["Server": "localhost", "Port": "1080"])
    #expect(await model.create(draft))
    let original = try #require(model.selected)
    var edited = original
    edited.document.set("Profile", "Name", "Uncommitted")
    for cancel in [false, true] {
        let candidate = try fixture.executable(gateCapabilities: true)
        model.selectCoreExecutable(candidate, timeout: .seconds(5))
        let started = URL(fileURLWithPath: candidate.path + ".capabilities-started")
        for _ in 0..<1000 {
            if FileManager.default.fileExists(atPath: started.path) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(FileManager.default.fileExists(atPath: started.path))
        #expect(model.coreSelection.statusKey.contains("checking"))
        #expect(await model.create(draft) == false)
        #expect(await model.save(edited, original: original) == false)
        #expect(try await model.library.load().profiles == [original])
        #expect(model.selected == original)
        if cancel { model.cancelCoreProbe() }
        await model.waitForCoreProbe()
        #expect(model.coreSelection.statusKey.contains("failed"))
        #expect(await model.create(draft) == false)
        #expect(await model.save(edited, original: original) == false)
        #expect(try await model.library.load().profiles == [original])
        #expect(model.selected == original)
        #expect(edited.document.name == "Uncommitted")
    }
}

@Test @MainActor func probeTimeoutCancellationAndStaleResultsCannotActivate() async throws {
    let fixture = try SelectionFixture()
    defer { fixture.remove() }
    let settings = try IsolatedAppSettings()
    let slow = try fixture.executable(delay: true)
    let fast = try fixture.executable()
    let model = AppModel(coreCLI: nil, defaults: settings.defaults)
    model.selectCoreExecutable(slow, timeout: .milliseconds(30))
    await model.waitForCoreProbe()
    #expect(model.coreSelection.statusKey.contains("failed"))
    model.selectCoreExecutable(slow)
    try await Task.sleep(for: .milliseconds(20))
    model.cancelCoreProbe()
    #expect(model.coreSelection.statusKey.contains("failed"))
    model.selectCoreExecutable(slow)
    try await Task.sleep(for: .milliseconds(20))
    model.selectCoreExecutable(fast)
    await model.waitForCoreProbe()
    try await Task.sleep(for: .milliseconds(300))
    #expect(model.coreSelection.statusKey.contains("UNTRUSTED"))
    model.selectCoreExecutable(slow)
    try await Task.sleep(for: .milliseconds(20))
    model.resetCoreExecutable()
    try await Task.sleep(for: .milliseconds(300))
    #expect(model.coreSelection.statusKey.contains("default"))
}

@Test @MainActor func selectionIsFrozenDuringCreateAndSaveValidation() async throws {
    let fixture = try SelectionFixture()
    defer { fixture.remove() }
    let settings = try IsolatedAppSettings()
    let gate = try fixture.executable(gateValidation: true)
    let rejecting = try fixture.executable(validation: 1)
    let model = AppModel(library: ProfileLibrary(directory: fixture.root.appending(path: "profiles")),
                         coreCLI: CoreCLI(executableURL: rejecting), defaults: settings.defaults)
    model.selectCoreExecutable(gate, timeout: .seconds(2))
    await model.waitForCoreProbe()
    let draft = try EditorProtocol.socks5.document(name: "Draft", values: ["Server": "localhost", "Port": "1080"])
    for saving in [false, true] {
        let original = model.selected
        let operation = Task {
            if saving, let original { return await model.save(original, original: original) }
            return await model.create(draft)
        }
        let started = URL(fileURLWithPath: gate.path + ".started")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: started.path) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(FileManager.default.fileExists(atPath: started.path))
        #expect(model.validationBusy)
        model.resetCoreExecutable()
        model.selectCoreExecutable(rejecting)
        model.cancelCoreProbe()
        #expect(model.coreSelection.statusKey.contains("UNTRUSTED"))
        try Data().write(to: URL(fileURLWithPath: gate.path + ".release"))
        #expect(await operation.value)
        #expect(!model.validationBusy)
        try FileManager.default.removeItem(at: started)
        try FileManager.default.removeItem(atPath: gate.path + ".release")
    }
}
