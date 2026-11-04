import Foundation
import Testing
import BimeronCoreCLI
import BimeronModel
@testable import BimeronApp

@Test @MainActor func editorCreationRequiresActualCLIAndRetainsDraftOnFailure() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let library = ProfileLibrary(directory: root.appending(path: "profiles"))
    let draft = try EditorProtocol.socks5.document(name: "Draft", values: ["Server": "localhost", "Port": "1080"])
    let original = draft.text
    let unavailable = AppModel(library: library, coreCLI: nil)
    #expect(await unavailable.create(draft) == false)
    #expect(try await library.load().profiles.isEmpty)
    let executable = root.appending(path: "fixture-core")
    try Data("#!/bin/sh\ntest \"$1\" = validate || exit 2\ntest -f \"$2\" || exit 3\nexit 1\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let model = AppModel(library: library, coreCLI: CoreCLI(executableURL: executable))
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
    let library = ProfileLibrary(directory: root.appending(path: "profiles"))
    let model = AppModel(library: library, coreCLI: nil)
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
