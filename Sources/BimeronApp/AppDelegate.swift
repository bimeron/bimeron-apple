import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var quitting = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        Task {
            // Refresh even with no window: window-scoped monitoring may have stopped.
            await model.connection.refreshForQuit()
            guard QuitDecision.needsConfirmation(reachable: model.connection.reachable,
                                                 active: model.connection.active) else {
                sender.reply(toApplicationShouldTerminate: true)
                return
            }
            sender.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = model.t("Quit with an active VPN session?")
            alert.addButton(withTitle: model.t("Disconnect and quit"))
            alert.addButton(withTitle: model.t("Quit, keep VPN running"))
            alert.addButton(withTitle: model.t("Cancel")).keyEquivalent = "\u{1b}"
            let choice: QuitDecision.Choice = switch alert.runModal() {
            case .alertFirstButtonReturn: .disconnect
            case .alertSecondButtonReturn: .keepRunning
            default: .cancel
            }
            let outcome = await QuitDecision.resolve(choice) { await self.model.connection.stopForQuit() }
            sender.reply(toApplicationShouldTerminate: outcome == .terminate)
            quitting = false
            if case .error(let key) = outcome {
                let error = NSAlert()
                error.alertStyle = .warning
                error.messageText = model.t(key)
                error.runModal()
            }
        }
        return .terminateLater
    }
}
