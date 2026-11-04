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
