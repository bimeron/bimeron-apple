import Foundation
import Testing
@testable import BimeronModel

@Test func dynamicShadowsocksIsDistinguishedFromStatic() throws {
    let staticProfile = try ConfigDocument.new(name: "Static", key: "ss://example")
    let dynamicProfile = try ConfigDocument.new(name: "Dynamic", key: "ssconf://example")
    let importedKey = try ConfigDocument("[AccessKey]\nKey = ssconf://example")
    #expect(staticProfile.protocolName == "Shadowsocks")
    #expect(dynamicProfile.protocolName == "Shadowsocks ⟳")
    #expect(importedKey.protocolName == "Shadowsocks ⟳")
}

@Test func profileRoundTripAndPrivateStorage() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let doc = try ConfigDocument.new(name: "Test", key: "ss://example")
    let saved = try await library.add(doc)
    let loaded = try await library.load()
    #expect(loaded.profiles == [saved])
    let file = root.appending(path: saved.id.uuidString + ".conf")
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    var changed = saved
    changed.document.set("Profile", "Name", "New name")
    try await library.update(changed)
    #expect(try await library.load().profiles.first?.document.name == "New name")
    try await library.delete(saved.id)
    #expect(try await library.load().profiles.isEmpty)
    try await library.restore(changed)
    #expect(try await library.load().profiles == [changed])
    await #expect(throws: ProfileError.duplicate("Profile")) { try await library.restore(changed) }
    #expect(try await library.load().profiles == [changed])
}

@Test func failedImportLeavesNoProfile() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".conf")
    defer { try? FileManager.default.removeItem(at: original) }
    try Data("[Profile]\nVersion = 1\nName = Bad\n[AccessKey]\nFile = absent.key\n".utf8).write(to: original)
    let library = ProfileLibrary(directory: root)
    await #expect(throws: ProfileError.self) { try await library.importFile(original) }
    #expect(try await library.load().profiles.isEmpty)
}

@Test func profilesKeepCreationOrderAfterRename() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    var first = try await library.add(ConfigDocument.new(name: "Z", key: "ss://example"))
    let firstFile = root.appending(path: first.id.uuidString + ".conf")
    try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: firstFile.path)
    let second = try await library.add(ConfigDocument.new(name: "A", key: "ss://example"))
    #expect(try await library.load().profiles.map(\.id) == [first.id, second.id])
    first.document.set("Profile", "Name", "B")
    try await library.update(first)
    #expect(try await library.load().profiles.map(\.id) == [first.id, second.id])
}

@Test func legacyProfilesKeepAlphabeticalOrderOnFirstAdd() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let first = try await library.add(ConfigDocument.new(name: "Z", key: "ss://example"))
    let second = try await library.add(ConfigDocument.new(name: "A", key: "ss://example"))
    try FileManager.default.removeItem(at: root.appending(path: "order.json"))
    #expect(try await library.load().profiles.map(\.id) == [second.id, first.id])
    let third = try await library.add(ConfigDocument.new(name: "C", key: "ss://example"))
    #expect(try await library.load().profiles.map(\.id) == [second.id, first.id, third.id])
}

@Test func restoredProfileReturnsToOriginalPosition() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let first = try await library.add(ConfigDocument.new(name: "Z", key: "ss://example"))
    let file = root.appending(path: first.id.uuidString + ".conf")
    try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: file.path)
    let second = try await library.add(ConfigDocument.new(name: "A", key: "ss://example"))
    let created = try await library.delete(first.id)
    try await library.restore(first, created: created)
    #expect(try await library.load().profiles.map(\.id) == [first.id, second.id])
    try await library.delete(first.id)
    try await library.restore(first, created: created)
    #expect(try await library.load().profiles.map(\.id) == [first.id, second.id])
}

@Test func profileOrderSurvivesReloadAndRestore() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let first = try await library.add(ConfigDocument.new(name: "First", key: "ss://example"))
    let second = try await library.add(ConfigDocument.new(name: "Second", key: "ss://example"))
    let third = try await library.add(ConfigDocument.new(name: "Third", key: "ss://example"))
    for (index, profile) in [first, second, third].enumerated() {
        let file = root.appending(path: profile.id.uuidString + ".conf")
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: Double(index + 1))], ofItemAtPath: file.path)
    }
    #expect(try await library.move(third.id, by: -1).map(\.id) == [first.id, third.id, second.id])
    let reloaded = ProfileLibrary(directory: root)
    #expect(try await reloaded.load().profiles.map(\.id) == [first.id, third.id, second.id])
    let created = try await reloaded.delete(third.id)
    #expect(try await reloaded.move(second.id, by: -1).map(\.id) == [second.id, first.id])
    try await reloaded.restore(third, created: created)
    #expect(try await reloaded.load().profiles.map(\.id) == [second.id, third.id, first.id])
    let fourth = try await reloaded.add(ConfigDocument.new(name: "Fourth", key: "ss://example"))
    #expect(try await reloaded.load().profiles.map(\.id) == [second.id, third.id, first.id, fourth.id])
}

@Test func rawFieldsAndRuleOrderSurviveFormChange() throws {
    var doc = try ConfigDocument("[Profile]\nVersion = 1\nName = Old\n\n[AccessKey]\nVLESS = vless://example\nXFuture = keep\n\n[Interface]\nMode = vpn\n\n[Routing]\nDefault = proxy\n\n[Rule]\nDomain = first.example\nAction = direct\n\n# [Rule]\n# Domain = second.example\n# Action = block\n")
    doc.set("Profile", "Name", "New")
    #expect(doc.text.contains("XFuture = keep"))
    #expect(doc.rules.map(\.destination) == ["first.example", "second.example"])
    #expect(doc.rules.map(\.enabled) == [true, false])
    doc.moveRule(0, by: 1)
    #expect(doc.rules.map(\.destination) == ["second.example", "first.example"])
}

@Test func rejectBadDNSAndOversizedConfig() throws {
    var doc = try ConfigDocument.new(name: "N", key: "ss://example")
    doc.set("Interface", "DNS", "1.1.1.1, 1.1.1.1")
    #expect(throws: ProfileError.invalid("DNS")) { try doc.validateLocally() }
    #expect(throws: ProfileError.tooLarge) { try ConfigDocument(String(repeating: "x", count: 65_537)) }
}

@Test func importResolvesRelativeFileWithoutTouchingOriginal() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let source = root.appending(path: "source")
    let libraryDirectory = root.appending(path: "library")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let keyFile = source.appending(path: "private.key")
    try Data("ss://example\n".utf8).write(to: keyFile)
    let config = source.appending(path: "Café.conf")
    try Data("\u{FEFF}[Profile]\r\nVersion = 1\r\nName = \"Café with spaces\"\r\n[AccessKey]\r\nFile = private.key\r\n[Interface]\r\nMode = vpn\r\n[Routing]\r\nDefault = proxy\r\n".utf8).write(to: config)
    let library = ProfileLibrary(directory: libraryDirectory)
    let imported = try await library.importFile(config)
    #expect(imported.document.name == "Café with spaces")
    #expect(imported.document.source == "Key")
    #expect(imported.document.accessKey == "ss://example")
    #expect(imported.document.value("AccessKey", "File") == nil)
    #expect(try String(contentsOf: config, encoding: .utf8).contains("File = private.key"))
}

@Test func noPersistedChangeBeforeUpdate() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let original = try await library.add(ConfigDocument.new(name: "Original", key: "vless://example"))
    var draft = original
    draft.document.set("Profile", "Name", "Unsaved")
    #expect(try await library.load().profiles.first?.document.name == "Original")
}
