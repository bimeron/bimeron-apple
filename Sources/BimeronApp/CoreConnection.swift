import AppKit
import BimeronDaemon
import CryptoKit
import Foundation
import Observation

@MainActor @Observable final class CoreConnection {
    static let revision = "6b0d97a4ac96a903153a57d544751401b98d6909"
    private let client: DaemonClient
    private(set) var state: LifecycleState = .unknown
    private(set) var busy = false
    private(set) var actionError: String?
    private(set) var active = false
    private(set) var profileName: String?
    private(set) var installOpened = false
    private(set) var installError = false

    init(client: DaemonClient = DaemonClient(expectedRevision: CoreConnection.revision)) {
        self.client = client
    }

    var statusKey: String {
        switch state {
        case .unknown: "Core: unknown or unavailable"
        case .stopped: "Core: disconnected"
        case .connected: "Core: connected"
        case .connecting, .starting: "Core: connecting"
        case .reconnecting: "Core: reconnecting"
        case .stopping: "Core: stopping; cleanup pending"
        case .cleanupUnconfirmed: "Core: error; cleanup unconfirmed"
        case .failed: "Core: connection failed"
        }
    }

    var actionErrorKey: String? {
        guard let actionError else { return nil }
        switch actionError {
        case "invalid_configuration": return "Core rejected the configuration. Edit or validate the selected profile before trying again."
        case "ikev2_requires_foreground_user_session": return "IKEv2 is unavailable through daemon Start. Select another protocol."
        default: return "Core rejected the action. Check the profile and Core status before trying again."
        }
    }

    var canStart: Bool { !busy && state == .stopped && !active }
    var canStop: Bool { !busy && active && ![.unknown, .starting, .stopping].contains(state) }

    func monitor() async {
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: .seconds(1)) } catch { break }
        }
        await client.invalidate()
        state = .unknown
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        await client.reconcile()
        await update()
    }

    func start(file: URL) async {
        guard canStart else { return }
        busy = true
        defer { busy = false }
        // Fresh admission never resumes a session automatically after installation or reopening.
        await client.reconcile()
        guard await client.state == .stopped, await client.guardsSupported else {
            await update()
            return
        }
        let path = file.standardizedFileURL.path
        let id = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        await client.connect(DaemonProfile(id: id, configPath: path))
        await update()
    }

    func stop() async {
        guard canStop else { return }
        busy = true
        defer { busy = false }
        await client.disconnect()
        await update()
    }

    private func update() async {
        actionError = await client.actionError
        let supported = await client.guardsSupported
        let observed = await client.state
        state = supported ? observed : .unknown
        let session = await client.session
        active = session?.active == true
        profileName = session?.profile_name
    }

    /// Opens macOS Installer only; opening it is not installation or readiness evidence.
    func openInstaller() {
        guard !busy, !active else { return }
        do {
            guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
            let directory = resources.appending(path: "CoreInstall")
            let data = try Data(contentsOf: directory.appending(path: "manifest.json"))
            let manifest = try JSONDecoder().decode(BundledCoreManifest.self, from: data)
            let package = directory.appending(path: "Install Core.pkg")
            let digest = SHA256.hash(data: try Data(contentsOf: package)).map { String(format: "%02x", $0) }.joined()
            guard manifest.permitsOpening(revision: Self.revision, ownerUID: getuid(), packageSHA256: digest) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            installOpened = NSWorkspace.shared.open(package)
            installError = !installOpened
        } catch { installError = true }
    }
}
