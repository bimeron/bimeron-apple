import Foundation
import Testing
import BimeronModel

@Test func failedImportPreservesPopulatedLibraryAndSourceBytes() async throws {
    let root = try privatePreservationRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let original = source.appending(path: "Rejected.conf")
    try Data("\u{FEFF}# Keep this source verbatim\r\n[Profile]\r\nVersion = 1\r\nName = Rejected\r\n[AccessKey]\r\nFile = absent.key\r\nXFuture = retained\r\n".utf8).write(to: original)
    let directory = root.appending(path: "library")
    let library = try await populatedPreservationLibrary(at: directory)
    let sourceBefore = try preservationFiles(in: source)
    let libraryBefore = try preservationFiles(in: directory)

    await #expect(throws: ProfileError.unreadableKey) { try await library.importFile(original) }

    #expect(try preservationFiles(in: source) == sourceBefore)
    #expect(try preservationFiles(in: directory) == libraryBefore)
}

@Test(arguments: ["reject", "tamper", "cancel"])
func failedCreationPreservesExactDraftAndPopulatedLibrary(_ mode: String) async throws {
    let root = try privatePreservationRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = try await populatedPreservationLibrary(at: root)
    let before = try preservationFiles(in: root)
    let draftBytes = Data("\u{FEFF}# Retain draft formatting\r\n[Profile]\r\nVersion = 1\r\nName = Retained draft\r\nXFuture = untouched\r\n\r\n[AccessKey]\r\nKey = ss://example\r\n# Keep this trailing comment\r\n".utf8)
    let document = try ConfigDocument(data: draftBytes)
    let (validating, signal) = AsyncStream<CheckedContinuation<Void, Never>>.makeStream()
    let task = Task {
        defer { signal.finish() }
        return try await library.add(document) { url in
            if mode == "reject" { throw ProfileError.invalid("Core fixture") }
            if mode == "tamper" { try Data("tampered".utf8).write(to: url) }
            if mode == "cancel" {
                await withCheckedContinuation { continuation in
                    signal.yield(continuation)
                }
            }
        }
    }
    if mode == "cancel" {
        var validations = validating.makeAsyncIterator()
        let resume = try #require(await validations.next())
        task.cancel()
        resume.resume()
    }
    switch mode {
    case "reject":
        await #expect(throws: ProfileError.invalid("Core fixture")) { try await task.value }
    case "tamper":
        await #expect { try await task.value } throws: { error in
            if case EditorSaveError.changedStaging = error { return true }
            return false
        }
    default:
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    #expect(Data(document.text.utf8) == draftBytes)
    #expect(try preservationFiles(in: root) == before)
}

private func privatePreservationRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    return root
}

private func populatedPreservationLibrary(at directory: URL) async throws -> ProfileLibrary {
    let library = ProfileLibrary(directory: directory)
    _ = try await library.add(ConfigDocument.new(name: "First", key: "ss://first"))
    let second = try await library.add(ConfigDocument.new(name: "Second", key: "ss://second"))
    _ = try await library.move(second.id, by: -1)
    return library
}

private func preservationFiles(in directory: URL) throws -> [String: Data] {
    let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    return try Dictionary(uniqueKeysWithValues: entries.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
}
