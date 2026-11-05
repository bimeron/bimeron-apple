import Foundation
import Testing
import BimeronModel
@testable import BimeronCoreCLI
@testable import BimeronApp

@Suite @MainActor struct ProfileOperationDiagnosticTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pair(_ model: AppModel, kind: DiagnosticEvent.Kind,
                      outcome: DiagnosticEvent.Outcome) throws -> UUID {
        let events = model.log.compactMap(\.event).filter { $0.kind == kind }
        #expect(events.map(\.outcome) == [.started, outcome])
        #expect(events.allSatisfy { $0.source == .gui })
        let id = try #require(events.first?.attemptID)
        #expect(events.allSatisfy { $0.attemptID == id })
        return id
    }

    @Test(arguments: ["success", "reject", "unavailable", "missing", "timeout", "cancel", "rewrite", "local", "storage"])
    func createOutcomes(mode: String) async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = try IsolatedAppSettings()
        let directory = root.appending(path: "profiles")
        if mode == "storage" { try Data("blocked".utf8).write(to: directory) }
        let library = ProfileLibrary(directory: directory)
        let script = root.appending(path: "fake-core")
        let body: String
        switch mode {
        case "reject": body = "echo synthetic-output-secret; echo synthetic-error-secret >&2; exit 7"
        case "timeout", "cancel": body = "exec /bin/sleep 2"
        case "rewrite": body = "printf changed > \"$2\""
        default: body = "test \"$1\" = validate && test -f \"$2\""
        }
        try Data(body.utf8).write(to: script)
        let cli: CoreCLI?
        switch mode {
        case "unavailable": cli = nil
        case "missing": cli = CoreCLI(executableURL: root.appending(path: "absent"))
        default: cli = CoreCLI(testShellScript: script, timeout: mode == "timeout" ? .milliseconds(80) : .seconds(2))
        }
        let model = AppModel(library: library, coreCLI: cli, defaults: settings.defaults)
        var draft = try ConfigDocument.new(name: "synthetic-name-secret", key: "socks5://localhost:1080")
        if mode == "local" { draft.set("AccessKey", "SOCKS5", "invalid") }
        let frozenDraft = draft
        let task = Task {
            if mode == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
            return await model.create(frozenDraft)
        }
        #expect(await task.value == (mode == "success"))
        let outcome: DiagnosticEvent.Outcome
        switch mode {
        case "success": outcome = .success
        case "unavailable", "missing": outcome = .unavailable
        case "timeout": outcome = .timedOut
        case "cancel": outcome = .cancelled
        case "storage": outcome = .failed
        default: outcome = .rejected
        }
        let id = try pair(model, kind: .profileCreate, outcome: outcome)
        let validation = model.log.compactMap(\.event).filter { $0.kind == .validation }
        let neverValidated = ["unavailable", "local", "storage"].contains(mode)
        let validationOutcomes: [DiagnosticEvent.Outcome]
        if neverValidated { validationOutcomes = [] }
        else if mode == "success" || mode == "rewrite" { validationOutcomes = [.started, .success] }
        else { validationOutcomes = [.started] }
        #expect(validation.map(\.outcome) == validationOutcomes)
        #expect(validation.allSatisfy { $0.source == .coreCLI && $0.attemptID == id })
        #expect(!model.validationBusy)
        #expect(draft == frozenDraft)
        if mode != "storage" {
            let profiles = try await library.load().profiles
            #expect(profiles.count == (mode == "success" ? 1 : 0))
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasSuffix(".tmp") })
        }
        let exported = model.diagnosticSnapshot().text(includeFreeText: false)
        for secret in ["synthetic-name-secret", "synthetic-output-secret", "synthetic-error-secret", root.path, frozenDraft.text] {
            #expect(!exported.contains(secret))
        }
    }

    @Test func addAndImportHaveSingleDistinctAttemptsAndFrozenSnapshots() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = try IsolatedAppSettings()
        let model = AppModel(library: ProfileLibrary(directory: root.appending(path: "profiles")),
                             coreCLI: nil, defaults: settings.defaults)
        #expect(await model.add(name: "synthetic-name-secret", key: "socks5://localhost:1080"))
        let first = try pair(model, kind: .profileAdd, outcome: .success)
        let snapshot = model.diagnosticSnapshot()
        let frozenText = snapshot.text(includeFreeText: false)
        model.clearLog()
        #expect(await model.addInput(name: "synthetic-name-secret", input: "'socks5://localhost:1080'"))
        let second = try pair(model, kind: .profileAdd, outcome: .success)
        #expect(second != first)
        #expect(model.log.compactMap(\.event).count == 2)
        let source = root.appending(path: "synthetic-path-secret.conf")
        let bytes = Data("[Profile]\nVersion=1\nName=synthetic-name-secret\n[AccessKey]\nSOCKS5=socks5://localhost:1080\n".utf8)
        try bytes.write(to: source)
        model.clearLog()
        #expect(await model.addInput(name: "", input: "'" + source.absoluteString + "'"))
        let third = try pair(model, kind: .profileImport, outcome: .success)
        #expect(model.log.compactMap(\.event).count == 2)
        model.clearLog()
        await model.importFile(source)
        let fourth = try pair(model, kind: .profileImport, outcome: .success)
        #expect(Set([first, second, third, fourth]).count == 4)
        #expect(try Data(contentsOf: source) == bytes)
        #expect(model.profiles.count == 4)
        #expect(model.selected != nil)
        #expect(snapshot.profileCount == 1)
        #expect(snapshot.text(includeFreeText: false) == frozenText)
        model.clearLog()
        #expect(snapshot.text(includeFreeText: false) == frozenText)
        #expect(!frozenText.contains("synthetic-name-secret"))
        #expect(!frozenText.contains(root.path))
    }

    @Test(arguments: ["add", "input", "import", "inputFile", "missingImport", "storage"])
    func localFailuresKeepDiagnosticsSanitized(mode: String) async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = try IsolatedAppSettings()
        let directory = root.appending(path: "profiles")
        if mode == "storage" { try Data("blocked".utf8).write(to: directory) }
        let model = AppModel(library: ProfileLibrary(directory: directory), coreCLI: nil, defaults: settings.defaults)
        let source = root.appending(path: "synthetic-path-secret.conf")
        try Data([0xff]).write(to: source)
        switch mode {
        case "add": #expect(await model.add(name: "synthetic-name-secret", key: "invalid") == false)
        case "input": #expect(await model.addInput(name: "synthetic-name-secret", input: "invalid") == false)
        case "inputFile": #expect(await model.addInput(name: "", input: source.absoluteString) == false)
        case "storage": #expect(await model.add(name: "synthetic-name-secret", key: "socks5://localhost:1080") == false)
        case "missingImport": await model.importFile(root.appending(path: "missing-secret.conf"))
        default: await model.importFile(source)
        }
        _ = try pair(model, kind: ["import", "inputFile", "missingImport"].contains(mode) ? .profileImport : .profileAdd,
                     outcome: mode == "storage" || mode == "missingImport" ? .failed : .rejected)
        #expect(model.profiles.isEmpty)
        #expect(model.alertMessage != nil)
        #expect(model.log.contains { $0.event == nil })
        let text = model.diagnosticSnapshot().text(includeFreeText: false)
        #expect(!text.contains("synthetic-name-secret"))
        #expect(!text.contains(root.path))
    }

    @Test(arguments: ["add", "input", "import", "inputFile"])
    func localOperationsPreserveExistingPreCancelledBehavior(mode: String) async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = try IsolatedAppSettings()
        let model = AppModel(library: ProfileLibrary(directory: root.appending(path: "profiles")),
                             coreCLI: nil, defaults: settings.defaults)
        let source = root.appending(path: "source.conf")
        let document = try ConfigDocument.new(name: "Synthetic", key: "socks5://localhost:1080")
        try Data(document.text.utf8).write(to: source)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            switch mode {
            case "add": return await model.add(name: "Synthetic", key: document.accessKey)
            case "input": return await model.addInput(name: "Synthetic", input: document.accessKey)
            case "inputFile": return await model.addInput(name: "", input: source.absoluteString)
            default:
                await model.importFile(source)
                return model.selectedID != nil
            }
        }
        #expect(await task.value)
        _ = try pair(model, kind: mode == "add" || mode == "input" ? .profileAdd : .profileImport, outcome: .success)
        #expect(model.profiles.count == 1)
    }

    @Test func busyCreateDoesNotStartAnotherAttempt() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = try IsolatedAppSettings()
        let script = root.appending(path: "fake-core")
        try Data("exec /bin/sleep 2".utf8).write(to: script)
        let model = AppModel(library: ProfileLibrary(directory: root.appending(path: "profiles")),
                             coreCLI: CoreCLI(testShellScript: script, timeout: .seconds(2)), defaults: settings.defaults)
        let draft = try ConfigDocument.new(name: "Synthetic", key: "socks5://localhost:1080")
        let task = Task { await model.create(draft) }
        defer { task.cancel() }
        for _ in 0..<1_000 {
            if model.validationBusy { break }
            await Task.yield()
        }
        try #require(model.validationBusy)
        let before = model.log.compactMap(\.event).filter { $0.kind == .profileCreate }
        #expect(await model.create(draft) == false)
        #expect(model.log.compactMap(\.event).filter { $0.kind == .profileCreate } == before)
        task.cancel()
        #expect(await task.value == false)
        _ = try pair(model, kind: .profileCreate, outcome: .cancelled)
    }
}
