import Foundation
import Testing
import BimeronModel
@testable import BimeronApp

private let routingSource = "[Routing]\nDefault = proxy\n[Rule]\nDomain=first.example\nAction = proxy\n# first comment\n[Rule]\nDomain = second.example\nAction = block\n; second comment"

@Test func routingRuleEditingStaleSnapshotNeverTargetsReplacement() throws {
    for operation in ["remove", "move", "raw", "add"] {
        var document = try ConfigDocument(routingSource)
        var state = RoutingRuleEditingState()
        state.selection = 0
        let snapshot = state.snapshot(document.rules[0])
        switch operation {
        case "remove": state.remove(from: &document)
        case "move": state.move(in: &document, by: 1)
        case "raw": state.acceptRaw(try ConfigDocument(routingSource.replacingOccurrences(of: "first.example", with: "replacement.example")), replacing: &document)
        default: state.add(to: &document)
        }
        #expect(document.rules.indices.contains(snapshot.rule.id))
        #expect(snapshot.read(from: document, state: state) == snapshot.rule)
        let before = document.text
        snapshot.write("stale.example", at: \.destination, to: &document, state: state)
        #expect(document.text == before)
    }
}

@Test func routingRuleEditingCurrentSnapshotSupportsRepeatedFieldWrites() throws {
    var document = try ConfigDocument(routingSource)
    let state = RoutingRuleEditingState()
    let snapshot = state.snapshot(document.rules[0])
    snapshot.write("edited.example", at: \.destination, to: &document, state: state)
    snapshot.write("direct", at: \.action, to: &document, state: state)
    #expect(snapshot.read(from: document, state: state).destination == "edited.example")
    #expect(document.rules[0].action == "direct")
    #expect(document.text.contains("# first comment"))
    #expect(document.text.contains("; second comment"))
}

@Test func routingRuleEditingSelectionAndUnchangedRawRoundTrip() throws {
    var document = try ConfigDocument(routingSource)
    var state = RoutingRuleEditingState()
    state.selection = 0
    state.move(in: &document, by: 1)
    #expect(state.selection == 1)
    #expect(document.rules[1].destination == "first.example")
    let generation = state.generation
    let before = document.text
    state.acceptRaw(try ConfigDocument(before), replacing: &document)
    #expect(state.selection == 1)
    #expect(state.generation == generation)
    #expect(document.text == before)
    state.add(to: &document)
    #expect(state.selection == 2)
    state.remove(from: &document)
    #expect(state.selection == nil)
    #expect(document.rules.count == 2)
}

@Test func routingRuleEditingInvalidMovesAreNoOps() throws {
    for index in [Int.min, -1, 0, 1, 2, Int.max] {
        for offset in [Int.min, -2, 0, 2, Int.max] {
            var document = try ConfigDocument(routingSource)
            var state = RoutingRuleEditingState()
            state.selection = index
            let generation = state.generation
            state.move(in: &document, by: offset)
            document.moveRule(index, by: offset)
            #expect(document.text == routingSource)
            #expect(state.selection == index)
            #expect(state.generation == generation)
        }
    }
    for (index, offset) in [(Int.min, -1), (Int.max, 1), (0, -1), (1, 1)] {
        var document = try ConfigDocument(routingSource)
        document.moveRule(index, by: offset)
        #expect(document.text == routingSource)
    }
}

@Test func routingRuleEditingMissingRowsAndRawAuthorityPreserveSource() throws {
    var document = try ConfigDocument(routingSource)
    var state = RoutingRuleEditingState()
    state.selection = 1
    let snapshot = state.snapshot(document.rules[1])
    state.remove(from: &document)
    #expect(snapshot.read(from: document, state: state) == snapshot.rule)
    snapshot.write(false, at: \.enabled, to: &document, state: state)
    #expect(document.rules[0].enabled)

    for suffix in ["Future = opaque\n", "CIDR = 1.2.3.0/24\n", "Domain = duplicate.example\n"] {
        let source = routingSource + "\n" + suffix
        var raw = try ConfigDocument(source)
        #expect(raw.formEditingIssue != nil)
        var rawState = RoutingRuleEditingState()
        rawState.selection = 0
        let rawSnapshot = rawState.snapshot(raw.rules[0])
        rawSnapshot.write("changed.example", at: \.destination, to: &raw, state: rawState)
        rawState.add(to: &raw)
        rawState.remove(from: &raw)
        rawState.move(in: &raw, by: 1)
        #expect(raw.text == source)
    }
}

@Test func routingRuleEditingGeneratedSourceRestoreInvalidatesOldRowSnapshot() throws {
    var drafts = ProtocolDrafts()
    let initial = try EditorProtocol.ss.document(name: "Restore", values: [:])
    _ = try drafts.select(.anytls, current: initial)
    _ = try drafts.set("Server", value: "example.com", name: "Restore")
    _ = try drafts.set("Port", value: "443", name: "Restore")
    let generated = try drafts.set("Password", value: "synthetic-password", name: "Restore")
    let ruleBlocks = routingSource.replacingOccurrences(of: "[Routing]\nDefault = proxy\n", with: "")
    var document = try ConfigDocument(generated.text + "\n" + ruleBlocks)
    #expect(document.formEditingIssue == nil)
    var state = RoutingRuleEditingState()
    state.selection = 0
    let snapshot = state.snapshot(document.rules[0])
    let editedRaw = try ConfigDocument(document.text.replacingOccurrences(of: "first.example", with: "replacement.example"))
    let restored = try drafts.restoringGeneratedSource(in: editedRaw)
    try drafts.checkParameterSource(restored)
    #expect(restored.formEditingIssue == nil)
    state.acceptRaw(restored, replacing: &document)
    #expect(state.selection == nil)
    #expect(document.rules[0].destination == "replacement.example")
    #expect(snapshot.read(from: document, state: state).destination == "first.example")
    let before = document.text
    snapshot.write("stale.example", at: \.destination, to: &document, state: state)
    #expect(document.text == before)
    #expect(document.text.contains("# first comment"))
}

@Test func routingRuleEditingProtocolDraftReplacementInvalidatesOldRowSnapshot() throws {
    var drafts = ProtocolDrafts()
    let ruleBlocks = routingSource.replacingOccurrences(of: "[Routing]\nDefault = proxy\n", with: "")
    let initial = try EditorProtocol.ss.document(name: "Protocols", values: [:])
    let first = try ConfigDocument(initial.text + "\n" + ruleBlocks)
    let alternate = try drafts.select(.vless, current: first)
    let second = try ConfigDocument(alternate.text + "\n" + ruleBlocks.replacingOccurrences(of: "first.example", with: "replacement.example"))
    var document = try drafts.select(.ss, current: second)
    var state = RoutingRuleEditingState()
    state.selection = 0
    let snapshot = state.snapshot(document.rules[0])
    let replacement = try drafts.select(.vless, current: document)
    #expect(replacement.formEditingIssue == nil)
    state.acceptRaw(replacement, replacing: &document)
    #expect(drafts.selected == .vless)
    #expect(state.selection == nil)
    #expect(document.rules[0].destination == "replacement.example")
    #expect(snapshot.read(from: document, state: state).destination == "first.example")
    let before = document.text
    snapshot.write("stale.example", at: \.destination, to: &document, state: state)
    #expect(document.text == before)
}
