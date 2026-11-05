import BimeronModel
import Foundation
import Testing
@testable import BimeronApp

@Test @MainActor func encodedImportSelectionPreservesTrailingFilenameSpace() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let source = root.appending(path: "source", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }

    let neighbor = source.appending(path: "Profile.conf")
    let selected = source.appending(path: "Profile.conf ")
    let neighborDocument = try ConfigDocument.new(name: "Unselected neighbor", key: "ss://neighbor")
    let selectedDocument = try ConfigDocument.new(name: "Selected file", key: "ss://selected")
    let neighborBytes = Data(neighborDocument.text.utf8)
    let selectedBytes = Data(selectedDocument.text.utf8)
    try neighborBytes.write(to: neighbor)
    try selectedBytes.write(to: selected)

    // Pasted-input whitespace normalization makes a raw panel path ambiguous for these fixtures.
    #expect(ProfileInput.normalized(selected.path) == neighbor.path)
    let input = selected.absoluteString
    #expect(ProfileInput.fileURL(input)?.path == selected.path)

    let settings = try IsolatedAppSettings()
    let library = ProfileLibrary(directory: root.appending(path: "library"))
    let model = AppModel(library: library, coreCLI: nil, defaults: settings.defaults)

    #expect(await model.addInput(name: "", input: input))
    #expect(model.alertMessage == nil)
    #expect(model.profiles.count == 1)
    let imported = try #require(model.selected)
    #expect(imported.document.name == selectedDocument.name)
    #expect(imported.document.accessKey == selectedDocument.accessKey)
    #expect(try await library.load().profiles == [imported])
    #expect(try Data(contentsOf: selected) == selectedBytes)
    #expect(try Data(contentsOf: neighbor) == neighborBytes)
}
