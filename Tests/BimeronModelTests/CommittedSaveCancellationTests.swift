import Foundation
import Testing
import BimeronModel

@Test func cancellationAfterCreationCommitPreservesReturnedProfileAndReload() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let document = try ConfigDocument.new(name: "Committed creation", key: "ss://example")
    let (committed, signal) = AsyncStream<CheckedContinuation<Void, Never>>.makeStream()
    let task = Task {
        defer { signal.finish() }
        let profile = try await library.add(document) { _ in }
        // Pause after the real commit, before the caller reloads, without a production hook.
        await withCheckedContinuation { continuation in
            signal.yield(continuation)
        }
        return (Task.isCancelled, profile, try await ProfileLibrary(directory: root).load().profiles)
    }
    var commits = committed.makeAsyncIterator()
    let resume = try #require(await commits.next())
    task.cancel()
    resume.resume()
    let (cancelled, profile, profiles) = try await task.value
    #expect(cancelled)
    #expect(profile.document == document)
    #expect(profiles == [profile])
    #expect(try Data(contentsOf: root.appending(path: profile.id.uuidString + ".conf")) == Data(document.text.utf8))
    #expect(try Set(FileManager.default.contentsOfDirectory(atPath: root.path)) == [profile.id.uuidString + ".conf", "order.json"])
}

@Test func cancellationAfterEditorCommitPreservesSuccessAndReload() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ProfileLibrary(directory: root)
    let original = try await library.add(ConfigDocument.new(name: "Original", key: "ss://example"))
    var draft = original
    draft.document.set("Profile", "Name", "Committed")
    let saved = draft
    let (committed, signal) = AsyncStream<CheckedContinuation<Void, Never>>.makeStream()
    let task = Task {
        try await library.update(saved, expectedOriginal: Data(original.document.text.utf8)) { _ in }
        // Pause after the real commit, before the caller reloads, without a production hook.
        await withCheckedContinuation { continuation in
            signal.yield(continuation)
        }
        return (Task.isCancelled, try await library.load().profiles)
    }
    var commits = committed.makeAsyncIterator()
    let resume = try #require(await commits.next())
    task.cancel()
    resume.resume()
    let (cancelled, profiles) = try await task.value
    #expect(cancelled)
    #expect(profiles == [saved])
    #expect(try Data(contentsOf: root.appending(path: original.id.uuidString + ".conf")) == Data(saved.document.text.utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasSuffix(".tmp") })
}
