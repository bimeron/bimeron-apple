import Foundation
import Testing
import BimeronModel

@Test func editorVariantsKeepIndependentDrafts() throws {
    #expect(EditorProtocol.allCases.count == 14)
    var drafts = ProtocolDrafts()
    var ss = try EditorProtocol.ss.document(name: "Draft", values: ["Server": "ss.example", "Password": "original", "Method": "aes-256-gcm"])
    ss.set("AccessKey", "Prefix", "retained")
    var vless = try drafts.select(.vless, current: ss)
    vless.set("AccessKey", "ID", "private-id")
    vless.set("AccessKey", "Security", "reality")
    let restored = try drafts.select(.ss, current: vless)
    #expect(restored.text == ss.text)
    #expect(try drafts.select(.vless, current: restored).text == vless.text)
    _ = try drafts.select(.tuic, current: vless)
    _ = try drafts.set("Password", value: "tuic secret", name: "Draft")
    let tuic = try drafts.set("Server", value: "tuic.example", name: "Draft")
    _ = try drafts.select(.anytls, current: tuic)
    _ = try drafts.set("Password", value: "other secret", name: "Draft")
    let anytls = try drafts.generatedDocument(name: "Draft")
    #expect(try drafts.select(.tuic, current: anytls).text == tuic.text)
    #expect(drafts.value("Password") == "tuic secret")
}

@Test func generatedURIContractsEscapeCredentialsAndIPv6() throws {
    let values = ["Server": "2001:db8::1", "Port": "8443", "Password": "p:@/?# %ю", "Username": "u:@", "ID": "id:@", "ServerName": "sni.example", "ALPN": "h3", "Fingerprint": "chrome"]
    for variant in [EditorProtocol.hysteria2, .tuic, .anytls, .naiveQUIC] {
        let uri = try variant.uri(values: values)
        #expect(uri.contains("@[2001:db8::1]:8443?sni=sni.example"))
        #expect(uri.contains("p%3A%40%2F%3F%23%20%25%D1%8E"))
        #expect(!uri.contains("#"))
        #expect(uri.contains("alpn=") == [.hysteria2, .tuic].contains(variant))
        #expect(uri.contains("fp=") == (variant == .hysteria2))
        if variant == .tuic { #expect(uri.hasPrefix("tuic://id%3A%40:")) }
        if variant == .naiveQUIC { #expect(uri.hasPrefix("naive+quic://u%3A%40:")) }
        try variant.document(name: "Generated", values: values).validateLocally()
    }
    let vmess = try EditorProtocol.vmess.uri(values: values.merging(["VMessNetwork": "ws", "VMessPath": "/a?b=ю", "VMessExtra": "{\"x\":true}"]) { _, new in new })
    let bytes = try #require(Data(base64Encoded: String(vmess.dropFirst("vmess://".count))))
    let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: String])
    #expect(object["add"] == "2001:db8::1")
    #expect(object["id"] == "id:@")
    #expect(object["aid"] == "0")
    #expect(object["path"] == "/a?b=ю")
    #expect(object["extra"] == "{\"x\":true}")
    #expect(object["ps"] == nil)
    #expect(throws: (any Error).self) { try EditorProtocol.anytls.uri(values: ["Server": "example", "Port": "0"]) }
    #expect(throws: (any Error).self) { try EditorProtocol.socks5.document(name: "Bad", values: ["Server": "a\nType=ssh"]) }
}

@Test func unifiedInputNormalizesOnlyMatchingQuotes() {
    #expect(ProfileInput.normalized(" 'ss://opaque' \n") == "ss://opaque")
    #expect(ProfileInput.normalized("'ss://opaque\"") == "'ss://opaque\"")
    #expect(ProfileInput.fileURL("\"file:///tmp/my%20profile.conf\"")?.path == "/tmp/my profile.conf")
    #expect(ProfileInput.fileURL("'~/profile.conf'")?.path == FileManager.default.homeDirectoryForCurrentUser.appending(path: "profile.conf").path)
    #expect(ProfileInput.fileURL("ss://example.conf") == nil)
}

@Test func vlessInspectionAndUnrelatedEditPreserveOpaqueURI() throws {
    let uri = "vless://private%40id@[2001:db8::1]:443?security=reality&type=ws&path=%2fa%3Fb&pbk=secret&future=x%2Fy#unchanged"
    var document = try ConfigDocument("\u{FEFF}[Profile]\r\nVersion=1\r\nName=Original\r\n[AccessKey]\r\nVLESS = \(uri)\r\n# unknown comment\r\n")
    let original = document.text
    #expect(document.vlessInspection.contains { $0.0 == "path" && $0.1 == "/a?b" })
    #expect(document.text == original)
    document.set("Profile", "Name", "Edited")
    #expect(document.text == original.replacingOccurrences(of: "Name=Original", with: "Name = Edited"))
    #expect(document.accessKey == uri)
}

@Test func shadowTLSGateAndDisabledDraftRestoreExactBytes() throws {
    var document = try ConfigDocument.new(name: "Test", key: "naive+quic://user:pass@example.com:443")
    #expect(document.shadowTLSCompatibilityIssue != nil)
    #expect(try ConfigDocument.new(name: "VLESS URI", key: "vless://id@example.com:443?security=none").shadowTLSCompatibilityIssue != nil)
    #expect(try ConfigDocument.new(name: "SS plugin", key: "ss://aes-256-gcm:secret@example.com:443?plugin=obfs-local").shadowTLSCompatibilityIssue != nil)
    document = try EditorProtocol.vless.document(name: "VLESS", values: ["Server": "example.com", "Port": "443", "Security": "none"])
    #expect(document.shadowTLSCompatibilityIssue != nil)
    document.set("AccessKey", "Security", "tls")
    #expect(document.shadowTLSCompatibilityIssue == nil)
    var ss = try EditorProtocol.ss.document(name: "SS", values: ["Server": "example.com", "Port": "443", "Method": "aes-256-gcm", "Plugin": "obfs-local"])
    #expect(ss.shadowTLSCompatibilityIssue != nil)
    ss.remove("AccessKey", "Plugin")
    #expect(ss.shadowTLSCompatibilityIssue == nil)
    var disabled = try ConfigDocument(ss.text + "#[ShadowTLS]\r\n#ServerName=cover.example\n# Password = wrapper\r\n# # tail\n")
    let bytes = Data(disabled.text.utf8)
    disabled.setShadowTLSEnabled(true)
    #expect(disabled.shadowTLSEnabled)
    disabled.setShadowTLSEnabled(false)
    #expect(Data(disabled.text.utf8) == bytes)
}

@Test func editorCreationValidatesProtectedExactBytesAndCommits() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let document = try ConfigDocument.new(name: "Created", key: "ss://example")
    let expected = Data(document.text.utf8)
    let profile = try await library.add(document) { url in
        #expect(url.deletingLastPathComponent().path == root.path)
        #expect(try Data(contentsOf: url) == expected)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }
    #expect(try await library.load().profiles == [profile])
    #expect(try Data(contentsOf: root.appending(path: profile.id.uuidString + ".conf")) == expected)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasSuffix(".tmp") })
}

@Test(arguments: ["reject", "tamper", "cancel"])
func editorCreationFailureLeavesNoPartialProfile(_ mode: String) async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let document = try ConfigDocument.new(name: "Retained draft", key: "ss://example")
    let task = Task {
        try await library.add(document) { url in
            if mode == "reject" { throw ProfileError.invalid("Core fixture") }
            if mode == "tamper" { try Data("tampered".utf8).write(to: url) }
            if mode == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }
    do { _ = try await task.value; Issue.record("Unexpected commit") } catch {}
    #expect(try await library.load().profiles.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    #expect(document.name == "Retained draft")
}

@Test func incompatibleExplicitOptionsRetainDraftAndOfferFeedback() throws {
    var ss = try EditorProtocol.ss.document(name: "SS", values: ["Server": "example", "Port": "443", "Method": "2022-blake3-aes-128-gcm", "Prefix": "keep-me"])
    #expect(ss.editorCompatibilityIssue != nil)
    #expect(ss.value("AccessKey", "Prefix") == "keep-me")
    ss.set("AccessKey", "Method", "aes-128-gcm")
    #expect(ss.editorCompatibilityIssue == nil)
    #expect(ss.value("AccessKey", "Prefix") == "keep-me")
    var vless = try EditorProtocol.vless.document(name: "VLESS", values: ["Server": "example", "Port": "443", "Security": "reality", "Network": "tcp", "Flow": "xtls-rprx-vision", "PublicKey": "retained-key"])
    #expect(vless.editorCompatibilityIssue == nil)
    vless.set("AccessKey", "Network", "ws")
    #expect(vless.editorCompatibilityIssue != nil)
    #expect(vless.value("AccessKey", "Flow") == "xtls-rprx-vision")
    #expect(vless.value("AccessKey", "PublicKey") == "retained-key")
    vless.set("AccessKey", "Network", "tcp")
    #expect(vless.editorCompatibilityIssue == nil)
}

@Test func generatedDraftGuardAllowsUnrelatedRawEditsButRejectsChangedSources() throws {
    var drafts = ProtocolDrafts()
    let ss = try EditorProtocol.ss.document(name: "Draft", values: [:])
    _ = try drafts.select(.vmess, current: ss)
    var generated = try drafts.set("Server", value: "example.com", name: "Draft")
    generated.set("Profile", "Name", "Renamed")
    generated.set("Routing", "Default", "direct")
    try drafts.checkParameterSource(generated)
    let other = try drafts.select(.ss, current: generated)
    #expect(try drafts.select(.vmess, current: other).text == generated.text)
    generated.set("AccessKey", "VMess", "vmess://modified")
    #expect(throws: (any Error).self) { try drafts.checkParameterSource(generated) }
    #expect(throws: (any Error).self) { try drafts.select(.ss, current: generated) }
    #expect(drafts.selected == .vmess)
    #expect(drafts.hasEdits)
}

@Test func generatedValuesValidateNamesAndEncodedLinks() throws {
    for name in ["bad\nName = injected", String(repeating: "x", count: 129), "nul\0"] {
        #expect(throws: ProfileError.invalid("Name")) { try EditorProtocol.vmess.document(name: name, values: [:]) }
    }
    #expect(throws: ProfileError.invalid("AccessKey")) {
        try EditorProtocol.anytls.document(name: "Safe", values: ["Server": "a b", "Password": "ok"])
    }
    let document = try EditorProtocol.vmess.document(name: "Safe", values: ["Server": "example.com"])
    let data = try #require(Data(base64Encoded: String(document.accessKey.dropFirst(8))))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
    #expect(object["scy"] == "auto")
    #expect(object["net"] == "tcp")
    #expect(object["tls"] == "tls")
}

@Test func inactiveDraftEditsSurviveReturningToInitialProtocol() throws {
    var drafts = ProtocolDrafts()
    let ss = try EditorProtocol.ss.document(name: "Draft", values: [:])
    _ = try drafts.select(.tuic, current: ss)
    let modified = try drafts.set("Password", value: "unsaved secret", name: "Draft")
    let restored = try drafts.select(.ss, current: modified)
    #expect(restored.text == ss.text)
    #expect(drafts.hasEdits)
}

@Test func tcpVLESSAllowsFalseGRPCMultiMode() throws {
    var document = try EditorProtocol.vless.document(name: "VLESS", values: ["Server": "example.com", "Security": "tls", "Network": "tcp", "GRPCMultiMode": "false"])
    #expect(document.editorCompatibilityIssue == nil)
    document.set("AccessKey", "GRPCMultiMode", "true")
    #expect(document.editorCompatibilityIssue != nil)
    document.set("AccessKey", "GRPCMultiMode", "false")
    document.set("AccessKey", "GRPCServiceName", "service")
    #expect(document.editorCompatibilityIssue != nil)
}

@Test func validatedCreationAppendsToVisibleOrder() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let zulu = try await library.add(ConfigDocument.new(name: "Zulu", key: "ss://example")) { _ in }
    let alpha = try await library.add(ConfigDocument.new(name: "Alpha", key: "ss://example")) { _ in }
    #expect(try await library.load().profiles.map(\.id) == [zulu.id, alpha.id])
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "order.json").path))
}

private actor OrderWarnings {
    var messages: [String] = []
    func append(_ message: String) { messages.append(message) }
}

@Test func orderFailureAfterCommitReturnsCreatedProfileAndWarning() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let warnings = OrderWarnings()
    let profile = try await library.add(ConfigDocument.new(name: "Created", key: "ss://example"), orderWarning: { await warnings.append($0) }) { _ in
        try FileManager.default.createDirectory(at: root.appending(path: "order.json"), withIntermediateDirectories: true)
    }
    #expect(try await library.load().profiles == [profile])
    #expect(await warnings.messages.count == 1)
}

@Test func generatedDraftGuardRejectsSourceReplacementAndAllowsExactRevert() throws {
    var drafts = ProtocolDrafts()
    _ = try drafts.select(.anytls, current: EditorProtocol.ss.document(name: "Draft", values: [:]))
    let original = try drafts.set("Server", value: "example.com", name: "Draft")
    var changed = original
    changed.removeSection("AccessKey")
    changed.set("AccessKey", "Key", original.accessKey)
    #expect(throws: ProfileError.invalid("GeneratedAccessKey")) { try drafts.checkParameterSource(changed) }
    try drafts.checkParameterSource(original)
    #expect(try drafts.select(.ss, current: original).isExplicit)
}

@Test func generatedFormSaveRequiresLatestParametersWhileRawRemainsAuthoritative() throws {
    var drafts = ProtocolDrafts()
    _ = try drafts.select(.anytls, current: EditorProtocol.ss.document(name: "Draft", values: [:]))
    _ = try drafts.set("Password", value: "secret", name: "Draft")
    var valid = try drafts.set("Server", value: "example.com", name: "Draft")
    try drafts.checkSave(valid, raw: false)
    valid.set("Routing", "Default", "direct")
    try drafts.checkSave(valid, raw: false)
    #expect(throws: (any Error).self) { try drafts.set("Server", value: "a b", name: "Draft") }
    #expect(drafts.value("Server") == "a b")
    #expect(throws: (any Error).self) { try drafts.checkSave(valid, raw: false) }
    try drafts.checkSave(valid, raw: true)
    let corrected = try drafts.set("Server", value: "example.com", name: "Draft")
    try drafts.checkSave(corrected, raw: false)
    var raw = corrected
    raw.set("AccessKey", "AnyTLS", "anytls://secret@changed.example:443")
    #expect(throws: ProfileError.invalid("GeneratedAccessKey")) { try drafts.checkSave(raw, raw: false) }
    #expect(throws: ProfileError.invalid("GeneratedAccessKey")) { try drafts.checkParameterSource(raw) }
    try drafts.checkSave(raw, raw: true)
}

@Test func generatedRestorePreservesBytesAndRefusesConflictingRawSchemas() throws {
    var drafts = ProtocolDrafts()
    _ = try drafts.select(.anytls, current: EditorProtocol.ss.document(name: "Draft", values: [:]))
    _ = try drafts.set("Password", value: "secret", name: "Draft")
    let generated = try drafts.set("Server", value: "example.com", name: "Draft")
    let source = "\u{FEFF}[Profile]\r\nVersion = 1\r\nName = Renamed\r\n[AccessKey]\r\n; keep comment\r\nFuture = opaque\r\n  AnyTLS  =  \"\(generated.accessKey)\"  \r\n# EOF"
    let original = try ConfigDocument(source)
    #expect(Data(try drafts.restoringGeneratedSource(in: original).text.utf8) == Data(source.utf8))
    let changed = source.replacingOccurrences(of: generated.accessKey, with: "anytls://secret@changed.example:443")
    let restored = try drafts.restoringGeneratedSource(in: ConfigDocument(changed))
    // A replacement changes only the encoded value; surrounding whitespace and all other bytes survive.
    let expected = source.replacingOccurrences(of: "\"\(generated.accessKey)\"", with: generated.accessKey)
    #expect(Data(restored.text.utf8) == Data(expected.utf8))
    try drafts.checkParameterSource(restored)
    for conflict in ["Key = anytls://secret@other.example:443", "Type = anytls", "Server = other.example"] {
        let raw = try ConfigDocument(source.replacingOccurrences(of: "# EOF", with: conflict + "\r\n# EOF"))
        #expect(throws: ProfileError.invalid("GeneratedAccessKey")) { try drafts.restoringGeneratedSource(in: raw) }
        #expect(raw.text.contains("Future = opaque\r\n"))
    }
    let different = try ConfigDocument(source.replacingOccurrences(of: "AnyTLS  =", with: "Key  ="))
    #expect(throws: ProfileError.invalid("GeneratedAccessKey")) { try drafts.restoringGeneratedSource(in: different) }
}
