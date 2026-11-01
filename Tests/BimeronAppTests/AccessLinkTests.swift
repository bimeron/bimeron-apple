import BimeronModel
import Foundation
import Testing
@testable import BimeronApp

@Test @MainActor func addDialogAcceptsCurrentCoreSchemesIncludingTrojan() {
    for link in ["trojan://password@example.com:443", "vmess://encoded", "https://example.com:443",
                 "masque://example.com:443", "naive+quic://user:password@example.com:443",
                 "hysteria2://password@example.com:443", "hy2://password@example.com:443",
                 "anytls://password@example.com:443", "ssh://user@example.com:22", "tuic://example.com:443"] {
        #expect(AddProfileView.accepts("\n " + link + " \n"))
    }
    #expect(!AddProfileView.accepts("https://"))
    #expect(!AddProfileView.accepts("wireguard://example.com"))
}

@Test @MainActor func addingSSHProfilePersistsOnlyTheOptionalIdentityPath() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let identity = directory.appending(path: "private key")
    let contents = Data("placeholder private key contents".utf8)
    try contents.write(to: identity)
    let suite = "BimeronSSHAddTests-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let library = ProfileLibrary(directory: directory.appending(path: "profiles"))
    let model = AppModel(library: library, defaults: defaults)

    #expect(await model.add(name: "SSH with identity", key: "ssh://alice@example.com:22", sshIdentityFile: identity))
    let saved = try #require(try await library.load().profiles.first)
    #expect(saved.document.value("AccessKey", "IdentityFile") == identity.path)
    #expect(saved.document.accessKey == "ssh://alice@example.com:22")
    #expect(!saved.document.text.contains("placeholder private key contents"))
    #expect(try Data(contentsOf: identity) == contents)

    #expect(await model.add(name: "SSH without identity", key: "ssh://alice@example.com:22"))
    #expect(model.selected?.document.value("AccessKey", "IdentityFile") == nil)
    #expect(await model.add(name: "Other protocol", key: "trojan://password@example.com:443", sshIdentityFile: identity))
    #expect(model.selected?.document.value("AccessKey", "IdentityFile") == nil)
}
