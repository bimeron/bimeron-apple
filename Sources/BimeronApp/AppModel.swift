import BimeronCoreCLI
import BimeronModel
import Foundation
import Observation

@MainActor @Observable final class AppModel {
    var page: Page = .profiles
    var profiles: [StoredProfile] = []
    var selectedID: UUID?
    var showDeleteDialog = false
    private var deletedProfiles: [(profile: StoredProfile, created: Date)] = []
    private var restoredProfiles: [(profile: StoredProfile, created: Date)] = []
    private(set) var historyBusy = false
    private(set) var orderBusy = false
    var alertMessage: String?
    private var diagnosticHistory = DiagnosticHistory()
    var log: [LogEntry] { diagnosticHistory.entries }
    var language: String { didSet { defaults.set(language, forKey: "language") } }
    var theme: String { didSet { defaults.set(theme, forKey: "theme") } }
    private let defaults: UserDefaults
    let library: ProfileLibrary
    private let coreCLI: CoreCLI?
    private(set) var coreSelection: SessionCoreSelection = .defaultResolver
    private(set) var validationBusy = false
    private var coreProbe: Task<Void, Never>?
    private var coreProbeGeneration = UUID()

    var coreSelectionStatus: String { t(coreSelection.statusKey) }
    private var validationCLI: CoreCLI? {
        switch coreSelection {
        case .defaultResolver: coreCLI
        case .compatible(let cli): cli
        case .probing, .blocked: nil
        }
    }

    /// Calling this method confirms consent to execute this candidate for metadata and validation.
    func selectCoreExecutable(_ url: URL, timeout: Duration = .seconds(10)) {
        guard !validationBusy else { return }
        coreProbe?.cancel()
        let generation = UUID()
        coreProbeGeneration = generation
        coreSelection = .probing
        let cli = CoreCLI(executableURL: url, timeout: timeout, outputLimit: 65_536)
        coreProbe = Task { [weak self] in
            do {
                try await SessionCoreSelection.probe(cli)
                guard let self, self.coreProbeGeneration == generation, !Task.isCancelled else { return }
                self.coreSelection = .compatible(cli)
                self.coreProbe = nil
            } catch {
                guard let self, self.coreProbeGeneration == generation else { return }
                self.coreSelection = .blocked
                self.coreProbe = nil
            }
        }
    }

    func cancelCoreProbe() {
        guard !validationBusy else { return }
        coreProbeGeneration = UUID()
        coreProbe?.cancel()
        coreProbe = nil
        coreSelection = .blocked
    }

    func resetCoreExecutable() {
        guard !validationBusy else { return }
        cancelCoreProbe()
        coreSelection = .defaultResolver
    }

    func waitForCoreProbe() async { await coreProbe?.value }

    var selected: StoredProfile? { profiles.first { $0.id == selectedID } }
    var canUndoDelete: Bool { !deletedProfiles.isEmpty && !historyBusy }
    var canRedoDelete: Bool { !restoredProfiles.isEmpty && !historyBusy }

    init(library: ProfileLibrary = ProfileLibrary(directory: ProfileLibrary.defaultDirectory()),
         coreCLI: CoreCLI? = AppModel.defaultCoreCLI(),
         defaults: UserDefaults = .standard,
         preferredLanguages: [String] = Locale.preferredLanguages) {
        self.library = library
        self.coreCLI = coreCLI
        self.defaults = defaults
        let saved = defaults.string(forKey: "language")
        let systemLanguage = preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
        if let saved, ["en", "ru"].contains(saved) {
            language = saved
        } else {
            language = systemLanguage == "ru" ? "ru" : "en"
        }
        theme = defaults.string(forKey: "theme") ?? "system"
    }

    func t(_ key: String) -> String { Localization.text(key, language: language) }

    func load() async {
        do {
            let snapshot = try await library.load()
            profiles = snapshot.profiles
            if !profiles.contains(where: { $0.id == selectedID }) { selectedID = nil }
            if snapshot.unreadableCount > 0 { alertMessage = t("Some profiles could not be read") }
        } catch { report(error) }
    }

    func add(name: String, key: String, sshIdentityFile: URL? = nil, sshKnownHostsFile: URL? = nil) async -> Bool {
        do {
            var document = try ConfigDocument.new(name: name, key: key)
            if document.accessProtocol == .ssh, let sshIdentityFile {
                document.set("AccessKey", "IdentityFile", sshIdentityFile.path)
            }
            if document.accessProtocol == .ssh, let sshKnownHostsFile {
                document.set("AccessKey", "KnownHostsFile", sshKnownHostsFile.path)
            }
            let profile = try await library.add(document)
            await load()
            selectedID = profile.id
            record(t("Profile added"))
            return true
        } catch { report(error); return false }
    }

    func create(_ document: ConfigDocument) async -> Bool {
        guard !validationBusy else { return false }
        validationBusy = true
        defer { validationBusy = false }
        guard let coreCLI = validationCLI else {
            alertMessage = t("Core validation is unavailable")
            return false
        }
        do {
            let profile = try await library.add(document, orderWarning: { message in
                await MainActor.run { self.alertMessage = self.t(message) }
            }) { url in
                _ = try await coreCLI.validate(fileURL: url)
            }
            await load()
            selectedID = profile.id
            record(t("Profile added"))
            return true
        } catch {
            let key: String
            switch error {
            case is CancellationError, CoreCLIError.cancelled: key = "Core validation cancelled"
            case CoreCLIError.launch: key = "Core validation is unavailable"
            case CoreCLIError.timedOut: key = "Core validation timed out"
            case is CoreCLIError: key = "Core rejected the configuration"
            case is EditorSaveError: key = "Staged profile changed; try saving again"
            default: report(error); return false
            }
            alertMessage = t(key)
            return false
        }
    }

    func addInput(name: String, input: String, sshIdentityFile: URL? = nil, sshKnownHostsFile: URL? = nil) async -> Bool {
        if let url = ProfileInput.fileURL(input) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let profile = try await library.importFile(url)
                await load()
                selectedID = profile.id
                record(t("Profile imported"))
                return true
            } catch { report(error); return false }
        }
        return await add(name: name, key: ProfileInput.normalized(input), sshIdentityFile: sshIdentityFile,
                         sshKnownHostsFile: sshKnownHostsFile)
    }

    func importFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let profile = try await library.importFile(url)
            await load()
            selectedID = profile.id
            record(t("Profile imported"))
        } catch { report(error) }
    }

    static func defaultCoreCLI() -> CoreCLI? {
        if let path = ProcessInfo.processInfo.environment["BIMERON_CORE_EXECUTABLE"] {
            guard path.hasPrefix("/") else { return nil }
            return CoreCLI(executableURL: URL(fileURLWithPath: path))
        }
        return Bundle.main.url(forAuxiliaryExecutable: "bimeron-core").map { CoreCLI(executableURL: $0) }
    }

    func save(_ profile: StoredProfile, original: StoredProfile) async -> Bool {
        guard !validationBusy else { return false }
        validationBusy = true
        defer { validationBusy = false }
        let cli = validationCLI
        let attemptID = UUID()
        recordProfileSave(.started, attemptID: attemptID)
        do {
            guard let coreCLI = cli else {
                let message = t("Core validation is unavailable")
                alertMessage = message
                recordProfileSave(.unavailable, attemptID: attemptID, message: message)
                return false
            }
            try await library.update(profile, expectedOriginal: Data(original.document.text.utf8)) { url in
                await MainActor.run {
                    self.record(DiagnosticEvent(source: .coreCLI, kind: .validation, outcome: .started, attemptID: attemptID))
                }
                _ = try await coreCLI.validate(fileURL: url)
                await MainActor.run {
                    self.record(DiagnosticEvent(source: .coreCLI, kind: .validation, outcome: .success, attemptID: attemptID))
                }
            }
            await load()
            selectedID = profile.id
            recordProfileSave(.success, attemptID: attemptID, message: t("Profile saved"))
            return true
        } catch {
            let key: String
            switch error {
            case is CancellationError: key = "Core validation cancelled"
            case CoreCLIError.cancelled: key = "Core validation cancelled"
            case CoreCLIError.launch: key = "Core validation is unavailable"
            case CoreCLIError.timedOut: key = "Core validation timed out"
            case is CoreCLIError: key = "Core rejected the configuration"
            case is EditorSaveError: key = "Profile changed; reopen it before saving"
            default:
                recordProfileSave(.failed, attemptID: attemptID)
                report(error); return false
            }
            let message = t(key)
            alertMessage = message
            let outcome: DiagnosticEvent.Outcome
            switch error {
            case is CancellationError, CoreCLIError.cancelled: outcome = .cancelled
            case CoreCLIError.launch: outcome = .unavailable
            case CoreCLIError.timedOut: outcome = .timedOut
            default: outcome = .rejected
            }
            recordProfileSave(outcome, attemptID: attemptID, message: message)
            return false
        }
    }

    func moveSelected(by offset: Int) async {
        guard !orderBusy, !historyBusy, let selectedID,
              let index = profiles.firstIndex(where: { $0.id == selectedID }),
              profiles.indices.contains(index + offset) else { return }
        orderBusy = true
        defer { orderBusy = false }
        do {
            profiles = try await library.move(selectedID, by: offset)
        } catch { report(error) }
    }

    func delete(_ profile: StoredProfile) async {
        guard !historyBusy, !orderBusy else { return }
        let nextSelection: UUID? = {
            guard selectedID == profile.id,
                  let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return selectedID }
            if index > 0 { return profiles[index - 1].id }
            return profiles.dropFirst().first?.id
        }()
        historyBusy = true
        defer { historyBusy = false }
        do {
            let created = try await library.delete(profile.id)
            deletedProfiles.append((profile, created))
            restoredProfiles.removeAll()
            self.selectedID = nextSelection
            await load()
            record(t("Profile removed"))
        } catch { report(error) }
    }

    func undoDelete() async {
        guard canUndoDelete, !orderBusy, let entry = deletedProfiles.last else { return }
        historyBusy = true
        defer { historyBusy = false }
        do {
            try await library.restore(entry.profile, created: entry.created)
            deletedProfiles.removeLast()
            restoredProfiles.append(entry)
            await load()
            selectedID = entry.profile.id
            record(t("Profile removal undone"))
        } catch { report(error) }
    }

    func redoDelete() async {
        guard canRedoDelete, !orderBusy, let entry = restoredProfiles.last else { return }
        historyBusy = true
        defer { historyBusy = false }
        do {
            try await library.delete(entry.profile.id)
            restoredProfiles.removeLast()
            deletedProfiles.append(entry)
            if selectedID == entry.profile.id { selectedID = nil }
            await load()
            record(t("Profile removal redone"))
        } catch { report(error) }
    }

    func record(_ message: String) {
        diagnosticHistory.append(message)
    }

    func clearLog() { diagnosticHistory.clear() }

    func diagnosticSnapshot() -> DiagnosticSnapshot {
        DiagnosticSnapshot(entries: log, profileCount: profiles.count)
    }

    func record(_ event: DiagnosticEvent) {
        diagnosticHistory.append(event.outcome.rawValue, event: event)
    }

    private func recordProfileSave(_ outcome: DiagnosticEvent.Outcome, attemptID: UUID, message: String? = nil) {
        let event = DiagnosticEvent(source: .gui, kind: .profileSave, outcome: outcome, attemptID: attemptID)
        diagnosticHistory.append(message ?? outcome.rawValue, event: event)
    }

    func report(_ error: Error) {
        let message: String
        if let failure = error as? ProfileError {
            switch failure {
            case .invalidUTF8: message = t("File must be UTF-8")
            case .tooLarge: message = t("Configuration exceeds 64 KiB")
            case .syntax(let line): message = t("Syntax error on line") + " \(line)"
            case .duplicate(let field): message = t("Duplicate field") + ": \(field)"
            case .missing(let field): message = t("Missing field") + ": \(field)"
            case .invalid(let field): message = t("Check field") + ": \(field)"
            case .unreadableKey: message = t("Could not read key file")
            }
        } else {
            message = t("File operation failed")
        }
        alertMessage = message
        record(message)
    }
}
