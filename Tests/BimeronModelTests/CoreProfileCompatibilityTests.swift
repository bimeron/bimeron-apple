import Foundation
import Testing
@testable import BimeronModel

private let accessLinks = [
    ("SS", "ss://YWVzLTI1Ni1nY206cmVwbGFjZS1tZQ@server.example.com:8388#Example"),
    ("SSConf", "ssconf://server.example.com/config?token=placeholder#Example"),
    ("SOCKS5", "socks5://user:placeholder@server.example.com:1080"),
    ("HTTP", "http://user:placeholder@server.example.com:8080"),
    ("HTTP", "https://server.example.com:443"),
    ("MASQUE", "masque://server.example.com:443"),
    ("VLESS", "vless://123e4567-e89b-12d3-a456-426614174000@server.example.com:443?encryption=none&type=xhttp&security=tls&extra=%7B%22noSSEHeader%22%3Atrue%7D#Example"),
    ("Trojan", "trojan://placeholder@server.example.com:443?security=tls&type=grpc&serviceName=proxy"),
    ("Naive", "naive+https://user:placeholder@server.example.com:443"),
    ("Naive", "naive+quic://user:placeholder@server.example.com:443"),
    ("Hysteria2", "hysteria2://placeholder@server.example.com:443?fp=chrome-146"),
    ("Hysteria2", "hy2://placeholder@server.example.com:443"),
    ("AnyTLS", "anytls://placeholder@server.example.com:443?sni=server.example.com"),
    ("SSH", "ssh://alice@server.example.com:22"),
    ("TUIC", "tuic://123e4567-e89b-12d3-a456-426614174000:placeholder@server.example.com:443?udp_relay_mode=quic"),
    ("VMess", "vmess://" + Data(#"{"v":"2","ps":"Example","add":"server.example.com","port":"443","id":"123e4567-e89b-12d3-a456-426614174000","aid":"0","scy":"auto","net":"ws","type":"none","host":"server.example.com","path":"/vmess","tls":"tls"}"#.utf8).base64EncodedString())
]

@Test func accessLinksSurviveCreationEditingAndReload() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = ProfileLibrary(directory: directory)
    for (source, link) in accessLinks {
        var profile = try await library.add(ConfigDocument.new(name: source, key: " \n" + link + "\n"))
        #expect(profile.document.source == source)
        #expect(profile.document.accessKey == link)
        #expect(profile.document.protocolName != "Config")
        profile.document.set("Profile", "Name", "Renamed " + source)
        try await library.update(profile)
        let reloaded = try await library.load().profiles.first { $0.id == profile.id }
        #expect(reloaded == profile)
        #expect(reloaded?.document.accessKey == link)
        var generic = profile.document
        generic.remove("AccessKey", source)
        generic.set("AccessKey", "Key", link)
        try generic.validateLocally()
        #expect(generic.protocolName == profile.document.protocolName)
    }
}

@Test func currentCoreExamplesImportWithoutLosingFields() async throws {
    let fixtures = try #require(Bundle.module.url(forResource: "CoreProfiles", withExtension: nil, subdirectory: "Fixtures"))
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = ProfileLibrary(directory: directory)
    let files = try FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "conf" }
    #expect(files.count == 23)
    for file in files {
        let original = try String(contentsOf: file, encoding: .utf8)
        let profile = try await library.importFile(file)
        #expect(profile.document.protocolName != "Config", "Unrecognized example: \(file.lastPathComponent)")
        #expect(profile.document.text == original, "Changed example: \(file.lastPathComponent)")
        var edited = profile
        edited.document.set("Profile", "Name", "Edited")
        try await library.update(edited)
        #expect(try await library.load().profiles.first { $0.id == edited.id } == edited)
        #expect(try String(contentsOf: file, encoding: .utf8) == original)
    }
}

@Test func fileBackedNewProtocolsImportWithoutChangingKeyFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = ProfileLibrary(directory: directory.appending(path: "library"))
    for (source, link) in accessLinks {
        let key = directory.appending(path: "access.key")
        let content = "\u{FEFF}" + link + "\n"
        try Data(content.utf8).write(to: key)
        let file = directory.appending(path: "profile.conf")
        try Data("[Profile]\nVersion = 1\nName = \(source)\n[AccessKey]\nFile = access.key\n".utf8).write(to: file)
        let imported = try await library.importFile(file)
        #expect(imported.document.source == "Key")
        #expect(imported.document.accessKey == link)
        #expect(imported.document.protocolName == ConfigDocument.protocolName(for: link))
        #expect(try Data(contentsOf: key) == Data(content.utf8))
    }
}

@Test func mixedSourcesWrongSchemesAndUnsupportedExplicitTypesAreRejected() throws {
    let prefix = "[Profile]\nVersion = 1\nName = Test\n[AccessKey]\n"
    for source in ["VMess = vmess://example\nTUIC = tuic://example", "VLESS = trojan://example",
                   "HTTP = masque://example", "Type = vmess\nServer = example.com\nPort = 443",
                   "Server = example.com\nPort = 443"] {
        let document = try ConfigDocument(prefix + source)
        #expect(throws: ProfileError.self) { try document.validateLocally() }
    }
    for link in ["wireguard://example", "vmess://", "hy2://bad value", "ssh://example\nPassword=secret"] {
        #expect(throws: ProfileError.invalid("AccessKey")) { try ConfigDocument.validateKey(link) }
    }
}

@Test func importedSSHAndMASQUEKeepFileReferencesAfterRelocation() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let source = directory.appending(path: "source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = ProfileLibrary(directory: directory.appending(path: "library"))
    let file = source.appending(path: "profile.conf")
    let link = "ssh://alice@example.com:22?identity=keys%2Fprivate%20key&known_hosts=keys%2Fknown_hosts"
    let text = "[Profile]\nVersion = 1\nName = SSH\n[AccessKey]\nSSH = \(link)\nKnownHostsFile = trusted_hosts\n"
    try Data(text.utf8).write(to: file)
    let ssh = try await library.importFile(file)
    #expect(ssh.document.accessKey == link)
    #expect(ssh.document.value("AccessKey", "IdentityFile") == source.appending(path: "keys/private key").path)
    #expect(ssh.document.value("AccessKey", "KnownHostsFile") == source.appending(path: "trusted_hosts").path)
    #expect(try String(contentsOf: file, encoding: .utf8) == text)

    let masque = "[Profile]\nVersion = 1\nName = MASQUE\n[AccessKey]\nType = masque\nServer = example.com\nPort = 443\nCAFile = certs/private.pem\n"
    try Data(masque.utf8).write(to: file)
    let imported = try await library.importFile(file)
    #expect(imported.document.value("AccessKey", "CAFile") == source.appending(path: "certs/private.pem").path)
}

@Test func removingOptionalFieldsAndShadowTLSKeepsSurroundingConfig() throws {
    var document = try ConfigDocument.new(name: "Test", key: "ss://example")
    document.set("AccessKey", "XFuture", "preserve")
    document.set("ShadowTLS", "ServerName", "handshake.example.com")
    #expect(throws: ProfileError.missing("ShadowTLS.Password")) { try document.validateLocally() }
    document.set("ShadowTLS", "Password", "placeholder")
    document.addRule()
    let rules = document.rules
    try document.validateLocally()
    document.remove("Interface", "IPv6")
    document.removeSection("ShadowTLS")
    try document.validateLocally()
    #expect(!document.hasSection("ShadowTLS"))
    #expect(document.value("Interface", "IPv6") == nil)
    #expect(document.value("AccessKey", "XFuture") == "preserve")
    #expect(document.rules == rules)
}

@Test func selectingProxyModeRemovesIncompatibleVPNOptions() throws {
    var document = try ConfigDocument.new(name: "Proxy", key: "trojan://example")
    document.set("Interface", "KillSwitch", "true")
    document.set("Interface", "Listen", "127.0.0.1:11080")
    document.setMode("proxy")
    try document.validateLocally()
    #expect(document.mode == "proxy")
    #expect(document.value("Interface", "IPv6") == nil)
    #expect(document.value("Interface", "KillSwitch") == nil)
    #expect(document.value("Interface", "Listen") == "127.0.0.1:11080")
    #expect(document.value("Interface", "DNS") == "1.1.1.1")
    #expect(document.accessKey == "trojan://example")
    document.setMode("vpn")
    try document.validateLocally()
}
