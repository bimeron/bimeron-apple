import Foundation
import Testing
@testable import BimeronCoreCLI
import BimeronModel
@testable import BimeronApp

@Test(arguments: [false, true]) @MainActor
func editorCreationPreservesGeneratedRawBytesAndRejectsCLIRewrite(rewrite: Bool) async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let settings = try IsolatedAppSettings()
    let directory = root.appending(path: "profiles")
    let library = ProfileLibrary(directory: directory)
    let generated = try EditorProtocol.anytls.document(name: "Draft", values: [
        "Server": "example.com", "Port": "443", "Password": "synthetic-password"
    ])
    let text = "\u{FEFF}[Profile]\r\nVersion = 1\r\nName = Raw draft\r\n[AccessKey]\r\n; retained comment\r\nAnyTLS = \(generated.accessKey)\r\nFuture = opaque\r\n# retained EOF"
    let draft = try ConfigDocument(text)
    let expected = root.appending(path: "expected")
    let captured = root.appending(path: "captured")
    try Data(text.utf8).write(to: expected)
    let script = root.appending(path: "fixture-core")
    try Data("""
    test "$#" = 2 && test "$1" = validate || exit 1
    test "$(dirname "$2")" = '\(directory.path)' || exit 2
    test "$(stat -f %Lp "$2")" = 600 || exit 3
    cmp "$2" '\(expected.path)' || exit 4
    cp "$2" '\(captured.path)' || exit 5
    \(rewrite ? "printf rewritten > \"$2\"" : "exit 0")
    """.utf8).write(to: script)
    let model = AppModel(library: library,
                         coreCLI: CoreCLI(testShellScript: script, timeout: .seconds(2)),
                         defaults: settings.defaults)

    #expect(await model.create(draft) == !rewrite)
    #expect(!model.validationBusy)
    #expect(draft.text == text)
    #expect(try Data(contentsOf: captured) == Data(text.utf8))
    let profiles = try await library.load().profiles
    if rewrite {
        #expect(profiles.isEmpty)
        #expect(model.selectedID == nil)
        #expect(model.alertMessage == model.t("Staged profile changed; try saving again"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    } else {
        let profile = try #require(profiles.first)
        #expect(profiles.count == 1)
        #expect(model.selectedID == profile.id)
        #expect(profile.document.text == text)
        #expect(try Data(contentsOf: directory.appending(path: profile.id.uuidString + ".conf")) == Data(text.utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.hasSuffix(".tmp") })
    }
}

@Test @MainActor func editorCreationRequiresActualCLIAndRetainsDraftOnFailure() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let settings = try IsolatedAppSettings()
    let library = ProfileLibrary(directory: root.appending(path: "profiles"))
    let draft = try EditorProtocol.socks5.document(name: "Draft", values: ["Server": "localhost", "Port": "1080"])
    let original = draft.text
    let unavailable = AppModel(library: library, coreCLI: nil, defaults: settings.defaults)
    #expect(await unavailable.create(draft) == false)
    #expect(try await library.load().profiles.isEmpty)
    let executable = root.appending(path: "fixture-core")
    try Data("#!/bin/sh\ntest \"$1\" = validate || exit 2\ntest -f \"$2\" || exit 3\nexit 1\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let model = AppModel(library: library, coreCLI: CoreCLI(executableURL: executable), defaults: settings.defaults)
    #expect(await model.create(draft) == false)
    #expect(draft.text == original)
    #expect(try await library.load().profiles.isEmpty)
    try Data("#!/bin/sh\ntest \"$1\" = validate || exit 2\ntest -f \"$2\" || exit 3\nexit 0\n".utf8).write(to: executable)
    #expect(await model.create(draft))
    #expect(model.selected?.document.text == original)
}

@Test @MainActor func unifiedAddImportsQuotedFileAndAddsQuotedURIWithLocalChecks() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let settings = try IsolatedAppSettings()
    let library = ProfileLibrary(directory: root.appending(path: "profiles"))
    let model = AppModel(library: library, coreCLI: nil, defaults: settings.defaults)
    let source = root.appending(path: "import source.conf")
    let bytes = Data("\u{FEFF}[Profile]\r\nVersion=1\r\nName=Imported\r\n[AccessKey]\r\nSOCKS5 = socks5://localhost:1080\r\n# retained\r\n".utf8)
    try bytes.write(to: source)
    #expect(AddProfileView.accepts("'" + source.path + "'"))
    #expect(await model.addInput(name: "", input: "'" + source.absoluteString + "'"))
    #expect(model.selected?.document.text == String(decoding: bytes, as: UTF8.self))
    #expect(try Data(contentsOf: source) == bytes)
    #expect(await model.addInput(name: "Quoted", input: "\"ssh://user@example.com:22\""))
    #expect(model.selected?.document.accessKey == "ssh://user@example.com:22")
}

@Test func protocolFieldMetadataMasksPluginOptionsAndNamesGeneratedFields() {
    #expect(ProtocolField.fields(for: .shadowsocks).first { $0.id == "PluginOpts" }?.secret == true)
    for key in EditorProtocol.vmess.fields {
        let field = ProtocolField.generated(key)
        #expect(!field.title.hasPrefix("VMess"))
        #expect(Localization.text(field.title, language: "en") == field.title)
        if !["ALPN"].contains(key) { #expect(Localization.text(field.title, language: "ru") != field.title) }
    }
}
