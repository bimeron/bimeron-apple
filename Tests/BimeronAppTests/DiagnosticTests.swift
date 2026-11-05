import Foundation
import Testing
import BimeronDaemon
import BimeronModel
import BimeronCoreCLI
@testable import BimeronApp

@Test func diagnosticDocumentRejectsCorruptInput() throws {
    let text = "Frozen diagnostics 🔐\n"
    #expect(try LogDocument(file: FileWrapper(regularFileWithContents: Data(text.utf8))).text == text)
    #expect(try LogDocument(file: FileWrapper(regularFileWithContents: Data())).text.isEmpty)
    #expect(throws: CocoaError.self) {
        try LogDocument(file: FileWrapper(regularFileWithContents: Data([0xFF])))
    }
    #expect(throws: CocoaError.self) {
        try LogDocument(file: FileWrapper(directoryWithFileWrappers: [:]))
    }
}

@Test @MainActor func diagnosticExportCancellationIsSilentAndFailuresAreSanitized() throws {
    #expect(DiagnosticExportView.reportableExportFailure(CancellationError()) == nil)
    #expect(DiagnosticExportView.reportableExportFailure(CocoaError(.userCancelled)) == nil)
    #expect(DiagnosticExportView.reportableExportFailure(
        NSError(domain: "Other", code: NSUserCancelledError)) != nil)

    let settings = try IsolatedAppSettings()
    let model = AppModel(coreCLI: nil, defaults: settings.defaults)
    let snapshot = model.diagnosticSnapshot()
    let reviewed = snapshot.text(includeFreeText: true)
    // Profile errors have interpolated details in report(); exporter errors must bypass those details.
    let failure = try #require(DiagnosticExportView.reportableExportFailure(
        ProfileError.invalid("password=secret /private/export.txt")))
    model.report(failure)
    #expect(model.alertMessage != nil)
    #expect(model.log.count == 1)
    #expect(!model.diagnosticSnapshot().text(includeFreeText: true).contains("secret"))
    #expect(!model.diagnosticSnapshot().text(includeFreeText: true).contains("/private"))
    #expect(snapshot.text(includeFreeText: true) == reviewed)
}

@Test func diagnosticHistoryEnforcesBothLimitsAndClear() {
    var history = DiagnosticHistory()
    for _ in 0...DiagnosticHistory.entryLimit { history.append("x") }
    #expect(history.entries.count == 5_000)
    history.append(String(repeating: "🔐", count: DiagnosticHistory.textLimit))
    #expect(history.entries.count == 1)
    #expect(history.textBytes == DiagnosticHistory.textLimit)
    #expect(!history.entries[0].message.contains("�"))
    history.append("é")
    #expect(history.textBytes == 2)
    history.clear()
    #expect(history.entries.isEmpty)
    #expect(history.textBytes == 0)
    history.append(String(repeating: "a", count: DiagnosticHistory.textLimit - 1) + "🔐")
    #expect(history.textBytes == DiagnosticHistory.textLimit - 1)
}

@Test @MainActor func diagnosticExportsRequireFreeTextOptInAndFreezeHistory() throws {
    let settings = try IsolatedAppSettings()
    let model = AppModel(coreCLI: nil, defaults: settings.defaults)
    let first = UUID()
    let second = UUID()
    model.record(DiagnosticEvent(source: .gui, kind: .profileSave, outcome: .started, attemptID: first))
    model.record("password=secret ssh://user:secret@host /private/key raw-error")
    model.record(DiagnosticEvent(source: .gui, kind: .profileSave, outcome: .unavailable, attemptID: first))
    model.record(DiagnosticEvent(source: .gui, kind: .profileSave, outcome: .started, attemptID: second))
    let snapshot = model.diagnosticSnapshot()
    let safe = snapshot.text(includeFreeText: false)
    #expect(!safe.contains("secret"))
    #expect(safe.contains("Latest retained lifecycle observation: unknown"))
    #expect(!safe.contains("/private"))
    #expect(safe.contains(first.uuidString))
    #expect(safe.contains(second.uuidString))
    #expect(snapshot.text(includeFreeText: true).contains("password=secret"))
    let document = LogDocument(text: safe)
    model.clearLog()
    model.record("later-secret")
    #expect(snapshot.text(includeFreeText: false) == safe)
    #expect(document.text == safe)
    #expect(!snapshot.text(includeFreeText: true).contains("later-secret"))
    #expect(model.log.count == 1)
    #expect(AppModel(coreCLI: nil, defaults: settings.defaults).log.isEmpty)
}

@Test func diagnosticLifecycleDoesNotClaimDisconnectedAfterIPCLoss() {
    var adapter = DiagnosticLifecycleAdapter()
    #expect(adapter.state == .unknown)
    let connected = LogEntry(message: "connected", event: adapter.observe(.connected))
    let retained = DiagnosticSnapshot(entries: [connected], profileCount: 0).text(includeFreeText: false)
    #expect(retained.contains("Latest retained lifecycle observation: connected"))
    #expect(!retained.contains("live state"))
    let lost = LogEntry(message: "unknown", event: adapter.lostIPC())
    let snapshot = DiagnosticSnapshot(entries: [connected, lost], profileCount: 0).text(includeFreeText: false)
    #expect(snapshot.contains("Latest retained lifecycle observation: unknown"))
    #expect(snapshot.contains("outcome=connected"))
    #expect(adapter.state == .unknown)
    #expect(adapter.observe(.cleanupUnconfirmed).outcome == .cleanupUnconfirmed)
}

@Test @MainActor func diagnosticSaveEventsFollowActualCLIValidation() async throws {
    let settings = try IsolatedAppSettings()
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root.appending(path: "profiles"))
    let original = try await library.add(ConfigDocument.new(name: "Original", key: "ss://example"))
    var draft = original
    draft.document.set("Profile", "Name", "Draft")
    let executable = root.appending(path: "fake-core")
    for rejected in [true, false] {
        let script = "#!/bin/sh\ntest \"$1\" = validate || exit 9\necho stderr-password-secret >&2\nexit \(rejected ? 1 : 0)\n"
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let model = AppModel(library: library, coreCLI: CoreCLI(executableURL: executable), defaults: settings.defaults)
        #expect(await model.save(draft, original: original) == !rejected)
        let events = model.log.compactMap(\.event)
        #expect(events.map(\.source) == (rejected ? [.gui, .coreCLI, .gui] : [.gui, .coreCLI, .coreCLI, .gui]))
        #expect(events.map(\.kind) == (rejected ? [.profileSave, .validation, .profileSave] : [.profileSave, .validation, .validation, .profileSave]))
        #expect(events.map(\.outcome) == (rejected ? [.started, .started, .rejected] : [.started, .started, .success, .success]))
        let attempt = try #require(events.first?.attemptID)
        #expect(events.allSatisfy { $0.attemptID == attempt })
        #expect(!model.diagnosticSnapshot().text(includeFreeText: true).contains("secret"))
        #expect(!model.diagnosticSnapshot().text(includeFreeText: false).contains(root.path))
        if !rejected {
            #expect(try await library.load().profiles == [draft])
            model.clearLog()
            #expect(await model.save(draft, original: draft))
            #expect(model.log.compactMap(\.event).map(\.outcome) == [.started, .started, .success, .success])
            model.clearLog()
            #expect(await model.save(original, original: original) == false)
            #expect(model.log.compactMap(\.event).map(\.outcome) == [.started, .started, .success, .rejected])
        }
    }
    let unavailable = AppModel(library: library, coreCLI: nil, defaults: settings.defaults)
    #expect(await unavailable.save(original, original: draft) == false)
    #expect(unavailable.log.compactMap(\.event).map(\.outcome) == [.started, .unavailable])
    #expect(unavailable.log.compactMap(\.event).allSatisfy { $0.source == .gui && $0.kind == .profileSave })
}
