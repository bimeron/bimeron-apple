import Testing
@testable import BimeronApp

@Test func quitConfirmationRequiresReachableActiveSession() {
    #expect(!QuitDecision.needsConfirmation(reachable: true, active: false))
    #expect(!QuitDecision.needsConfirmation(reachable: false, active: true))
    #expect(QuitDecision.needsConfirmation(reachable: true, active: true))
}

@MainActor @Test func quitChoices() async {
    #expect(await QuitDecision.resolve(.keepRunning) { Issue.record("Unexpected Stop"); return nil } == .terminate)
    #expect(await QuitDecision.resolve(.cancel) { Issue.record("Unexpected Stop"); return nil } == .stayOpen)
    #expect(await QuitDecision.resolve(.disconnect) { nil } == .terminate)
    #expect(await QuitDecision.resolve(.disconnect) { "Stop failed" } == .error("Stop failed"))
    #expect(await QuitDecision.resolve(.disconnect) { "Timeout" } == .error("Timeout"))
}
