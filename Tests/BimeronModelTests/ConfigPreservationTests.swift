import Foundation
import Testing
@testable import BimeronModel

private let preservationBase = "[Profile]\nVersion = 1\nName = Test\n[AccessKey]\nSS = ss://example\n[Interface]\nMode = vpn\n[Routing]\nDefault = proxy\n"

@Test func preservationNoOpRetainsEveryByte() throws {
    for source in ["", "\u{FEFF}", preservationBase, "\u{FEFF}" + preservationBase.replacing("\n", with: "\r\n"), "\u{FEFF}[Profile]\r\nName = \"Café\"\n; keep\r\nUnknown = a\\b#c;d=e"] {
        var document = try ConfigDocument(data: Data(source.utf8))
        #expect(Data(document.text.utf8) == Data(source.utf8))
        if let name = document.value("Profile", "Name") { document.set("Profile", "Name", name) }
        #expect(Data(document.text.utf8) == Data(source.utf8))
    }
}

@Test func preservationPointEditKeepsMixedEndingsAndUnknownContent() throws {
    let source = "\u{FEFF}[Profile]\r\nVersion = 1\nName=\"Old\"\r\n# comment\nFuture = \"keep\\tspelling\""
    var document = try ConfigDocument(source)
    document.set("Profile", "Name", "New")
    #expect(document.text == source.replacing("Name=\"Old\"", with: "Name = New"))
    document.set("Profile", "Extra", "a\\b#c;d=e\"f")
    #expect(document.text.contains("Extra = a\\b#c;d=e\"f\r\n"))
    #expect(document.value("Profile", "Extra") == "a\\b#c;d=e\"f")
}

@Test func preservationShadowTLSRoundTripKeepsSecretsAndComments() throws {
    let block = "[ShadowTLS]\r\nServerName=\"handshake.example\"\nPassword = \"  пароль\\t\\\\\\\"#;=  \"\r\n# original note"
    var document = try ConfigDocument("\u{FEFF}" + preservationBase + block)
    let password = document.shadowTLSValue("Password")
    #expect(document.formEditingIssue == nil)
    document.setShadowTLSEnabled(false)
    #expect(document.text.contains("# # original note"))
    #expect(!document.shadowTLSEnabled)
    let disabled = document.text
    document = try ConfigDocument(disabled)
    #expect(document.formEditingIssue == nil)
    #expect(document.shadowTLSValue("Password") == password)
    document.setShadowTLSEnabled(false)
    #expect(document.text == disabled)
    document.setShadowTLSEnabled(true)
    #expect(document.text == "\u{FEFF}" + preservationBase + block)
    document.setShadowTLSEnabled(true)
    #expect(document.text == "\u{FEFF}" + preservationBase + block)
}

@Test func preservationPartialDisabledDraftCanBeEditedAndCleared() throws {
    var document = try ConfigDocument(preservationBase)
    document.setShadowTLSValue("Password", "  ")
    #expect(!document.shadowTLSEnabled)
    #expect(!document.text.contains("ServerName ="))
    try document.validateLocally()
    document = try ConfigDocument(document.text)
    #expect(document.shadowTLSValue("Password") == "  ")
    document.setShadowTLSEnabled(true)
    #expect(throws: ProfileError.missing("ShadowTLS.ServerName")) { try document.validateLocally() }
    document.setShadowTLSEnabled(false)
    document.setShadowTLSValue("Password", "")
    #expect(!document.hasShadowTLSDraft)
    #expect(!document.text.contains("ShadowTLS"))
}

@Test func preservationAmbiguityLoadsInProtectedRaw() throws {
    for suffix in ["[ShadowTLS]\nUnknown = value\n", "[ShadowTLS]\nPassword = x\n[ShadowTLS]\nPassword = y", "# [ShadowTLS]\n# Password = x\n# Password = y", "# [ShadowTLS]\n# Password = \"\\u0041\"", "# [ShadowTLS]\n# Password = x\nActive = unsafe", "[Rule]\nDomain = example.com\nCIDR = 1.1.1.1\nAction = proxy", "[Interface]\nMode = proxy", "[Profile]\nName = \"\\/\""] {
        let source = preservationBase + suffix
        var document = try ConfigDocument(source)
        #expect(document.formEditingIssue != nil)
        document.setShadowTLSEnabled(false)
        #expect(Data(document.text.utf8) == Data(source.utf8))
    }
}

@Test func preservationFieldInsertionStaysOutsideDisabledDraft() throws {
    var document = try ConfigDocument(preservationBase + "# [ShadowTLS]\n# Password = secret")
    document.set("Routing", "Future", "false")
    #expect(document.text.contains("[Routing]\nFuture = false\nDefault = proxy\n# [ShadowTLS]"))
    #expect(try ConfigDocument(document.text).shadowTLSValue("Password") == "secret")
}

@Test func preservationRulesKeepQuotesCommentsAndBoundaries() throws {
    var document = try ConfigDocument("\u{FEFF}" + preservationBase + "[Rule]\r\nDomain=\"first.example\"\r\nAction=\"proxy\"\r\n# first\r\n[Rule]\nDomain = last.example\nAction = block\n# EOF")
    var rule = document.rules[0]
    rule.destination = "changed.example"
    document.updateRule(rule)
    #expect(document.text.contains("Domain = changed.example\r\nAction=\"proxy\"\r\n# first"))
    rule = document.rules[0]
    rule.enabled = false
    document.updateRule(rule)
    rule = document.rules[0]
    rule.enabled = true
    document.updateRule(rule)
    #expect(document.text.contains("# first"))
    document.moveRule(1, by: -1)
    let reopened = try ConfigDocument(document.text)
    #expect(reopened.rules.map(\.destination) == ["last.example", "changed.example"])
    #expect(document.text.contains("# EOF\n[Rule]"))
    #expect(document.text.hasPrefix("\u{FEFF}[Profile]"))
    #expect(document.text.filter { $0 == "\u{FEFF}" }.count == 1)
    document.removeRule(0)
    document.addRule()
    #expect(try ConfigDocument(document.text).rules.count == 2)
}

@Test func preservationLibraryNoOpAfterExplicitImportTransformation() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appending(path: "original.conf")
    let keyFile = root.appending(path: "key.txt")
    try Data("ss://example\n".utf8).write(to: keyFile)
    let source = "\u{FEFF}[Profile]\r\nVersion = 1\r\nName = Test\r\n[AccessKey]\r\nFile = key.txt\r\nCAFile = ca.pem\r\n# EOF"
    try Data(source.utf8).write(to: original)
    let directory = root.appending(path: "library")
    let library = ProfileLibrary(directory: directory)
    let imported = try await library.importFile(original)
    #expect(imported.document.accessKey == "ss://example")
    #expect(imported.document.value("AccessKey", "CAFile") == root.appending(path: "ca.pem").path)
    #expect(try Data(contentsOf: original) == Data(source.utf8))
    let saved = directory.appending(path: imported.id.uuidString + ".conf")
    let bytes = try Data(contentsOf: saved)
    let reopened = try #require(await library.load().profiles.first)
    try await library.update(reopened)
    #expect(try Data(contentsOf: saved) == bytes)
}

@Test func preservationOmittedDefaultsAndDecodedRuleNoOp() throws {
    let source = "[Interface]\nFuture = false\n[Rule]\nDomain=\"example.com\""
    var document = try ConfigDocument(source)
    document.setMode("vpn")
    document.updateRule(document.rules[0])
    #expect(document.text == source)
    var rule = document.rules[0]
    rule.destination = "changed.example"
    document.updateRule(rule)
    #expect(!document.text.contains("Action ="))
    #expect(!document.text.contains("Mode ="))
    #expect(document.value("Interface", "Future") == "false")
}

@Test func preservationDisabledEmptyAssignmentsAreOmittedAndIncompatibleDraftRetained() throws {
    var document = try ConfigDocument(preservationBase + "[ShadowTLS]\nServerName = \"\"\nPassword = secret\n# keep")
    document.setShadowTLSEnabled(false)
    #expect(!document.text.contains("ServerName ="))
    #expect(document.text.contains("# # keep"))
    let source = document.text.replacing("SS = ss://example", with: "Hysteria2 = hy2://example")
    document = try ConfigDocument(source)
    try document.validateLocally()
    document.setShadowTLSEnabled(true)
    let incompatible = document.text
    #expect(throws: ProfileError.invalid("ShadowTLS")) { try document.validateLocally() }
    #expect(document.text == incompatible)
    #expect(document.shadowTLSValue("Password") == "secret")
}

@Test func preservationLibraryReopensDisabledDraftAndProtectsDuplicateSections() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = ProfileLibrary(directory: directory)
    var document = try ConfigDocument("\u{FEFF}" + preservationBase + "[ShadowTLS]\nServerName = handshake.example\nPassword = \" secret \"\n# EOF")
    let active = document.text
    var profile = try await library.add(document)
    document.setShadowTLSEnabled(false)
    profile.document = document
    try await library.update(profile)
    var reopened = try #require(await library.load().profiles.first)
    #expect(!reopened.document.shadowTLSEnabled)
    #expect(reopened.document.shadowTLSValue("Password") == " secret ")
    #expect(reopened.document.text == document.text)
    reopened.document.setShadowTLSEnabled(true)
    try await library.update(reopened)
    #expect(try await library.load().profiles.first?.document.shadowTLSEnabled == true)
    #expect(try await library.load().profiles.first?.document.text == active)
    let file = directory.appending(path: profile.id.uuidString + ".conf")
    let ambiguous = reopened.document.text + "\n[Profile]\nName = duplicate"
    try Data(ambiguous.utf8).write(to: file)
    let protected = try #require(await library.load().profiles.first)
    #expect(protected.document.formEditingIssue != nil)
    #expect(throws: ProfileError.duplicate("Profile")) { try protected.document.validateLocally() }
    #expect(protected.document.text == ambiguous)
    #expect(try Data(contentsOf: file) == Data(ambiguous.utf8))
}

@Test func preservationOptionalClearingAndRequiredFieldValidation() throws {
    var document = try ConfigDocument(preservationBase)
    document.remove("Profile", "Name")
    document.set("AccessKey", "Prefix", "")
    document.remove("AccessKey", "Prefix")
    document.set("Interface", "KillSwitch", "false")
    document.set("AccessKey", "Future", "0")
    try document.validateLocally()
    #expect(document.value("Profile", "Name") == nil)
    #expect(document.value("AccessKey", "Prefix") == nil)
    #expect(document.value("Interface", "KillSwitch") == "false")
    #expect(document.value("AccessKey", "Future") == "0")
    document.set("AccessKey", "Password", "\u{8}")
    #expect(document.formEditingIssue != nil)
    #expect(throws: ProfileError.invalid("Value")) { try document.validateLocally() }
}

private struct PreservationAcceptanceManifest: Decodable {
    struct Scenario: Decodable {
        let id: String
        let fixture: String
        let expected_fixture: String?
        let operation: String?
    }
    let scenarios: [Scenario]
}

private func preservationAcceptanceRoot() throws -> URL {
    let configured = ProcessInfo.processInfo.environment["BIMERON_ACCEPTANCE_FIXTURE_ROOT"]
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let root = configured.map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? repository.appending(path: "fixtures/acceptance", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: root.appending(path: "manifest.json").path) else {
        throw NSError(domain: "PreservationAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "Missing D f8988b7 acceptance fixtures at \(root.path). Integrate D or set BIMERON_ACCEPTANCE_FIXTURE_ROOT to its fixtures/acceptance directory."])
    }
    return root
}

@Test(arguments: [
    "A-BOM-CRLF-NOOP", "A-BOM-CRLF-EDIT", "A-UNKNOWN-NOOP", "A-UNKNOWN-EDIT",
    "A-AMBIGUOUS-NOOP", "A-AMBIGUOUS-RAW", "A-DISABLED-SHADOWTLS-NOOP", "A-DISABLED-SHADOWTLS-EDIT"
])
func preservationAcceptanceByteFixture(_ scenarioID: String) async throws {
    let root = try preservationAcceptanceRoot()
    let manifest = try JSONDecoder().decode(PreservationAcceptanceManifest.self, from: Data(contentsOf: root.appending(path: "manifest.json")))
    let scenario = try #require(manifest.scenarios.first { $0.id == scenarioID })
    let input = try Data(contentsOf: root.appending(path: scenario.fixture))
    let expected = try Data(contentsOf: root.appending(path: #require(scenario.expected_fixture)))
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = ProfileLibrary(directory: directory)
    let original = StoredProfile(document: try ConfigDocument(data: input))
    // D's portable inputs omit required fields. Restore exercises the real writer without inventing validity.
    try await library.restore(original)
    var draft = try #require(await library.load().profiles.first).document
    #expect(Data(draft.text.utf8) == input)
    let canceledDraft = draft
    switch scenario.operation {
    case "edit":
        #expect(draft.formEditingIssue == nil)
        draft.set("Profile", "Name", "Edited")
    case "reject-visual-edit":
        #expect(draft.formEditingIssue != nil)
        // EditorView uses this same gate before exposing visual controls.
        if draft.formEditingIssue == nil { draft.set("Profile", "Name", "Edited") }
    case "noop":
        if scenarioID == "A-AMBIGUOUS-NOOP" { #expect(draft.formEditingIssue != nil) }
    default:
        Issue.record("Unknown preservation operation for \(scenarioID)")
    }
    #expect(Data(canceledDraft.text.utf8) == input)
    #expect(Data(draft.text.utf8) == expected)
    let originalFile = directory.appending(path: original.id.uuidString + ".conf")
    do {
        try await library.update(StoredProfile(id: original.id, document: draft))
        Issue.record("Incomplete portable fixture unexpectedly passed local validation")
    } catch {
        #expect(try Data(contentsOf: originalFile) == input)
    }
    let output = StoredProfile(document: draft)
    try await library.restore(output)
    #expect(try Data(contentsOf: directory.appending(path: output.id.uuidString + ".conf")) == expected)
    let reopened = try #require(await library.load().profiles.first { $0.id == output.id })
    #expect(Data(reopened.document.text.utf8) == expected)
    if scenarioID.hasPrefix("A-DISABLED-SHADOWTLS") {
        #expect(!reopened.document.shadowTLSEnabled)
        #expect(reopened.document.shadowTLSValue("Password") == "synthetic-only")
    }
}

@Test func preservationEmptyShadowTLSRemovalRetainsOriginalComments() throws {
    let comments = "# original note\r\n; second note\n\n# EOF without newline"
    let source = "\u{FEFF}" + preservationBase
    var empty = try ConfigDocument(source + "[ShadowTLS]\r\nServerName = \"\"\r\nPassword = \"\"\n" + comments)
    empty.setShadowTLSEnabled(false)
    #expect(Data(empty.text.utf8) == Data((source + comments).utf8))
    #expect(!empty.hasShadowTLSDraft)
    try empty.validateLocally()

    var populated = try ConfigDocument(source + "[ShadowTLS]\r\nServerName = handshake.example\r\nPassword = secret\n" + comments)
    populated.setShadowTLSEnabled(false)
    populated = try ConfigDocument(data: Data(populated.text.utf8))
    populated.setShadowTLSValue("ServerName", "")
    populated.setShadowTLSValue("Password", "")
    #expect(Data(populated.text.utf8) == Data((source + comments).utf8))
    #expect(!populated.hasShadowTLSDraft)
    #expect(try ConfigDocument(populated.text).formEditingIssue == nil)
    try populated.validateLocally()
}
