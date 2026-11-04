import Foundation
import Testing
@testable import BimeronGeoData

private let abcHash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
private enum Failure: Error { case injected }

private actor Transport: GeoDataTransport {
    var chunks: [Data]
    let fail: Bool
    let cancel: Bool
    init(_ chunks: [Data], fail: Bool = false, cancel: Bool = false) {
        self.chunks = chunks; self.fail = fail; self.cancel = cancel
    }
    func nextChunk(maxBytes: Int) async throws -> Data? {
        if !chunks.isEmpty {
            let chunk = chunks.removeFirst()
            if cancel && chunks.isEmpty { withUnsafeCurrentTask { $0?.cancel() } }
            return chunk
        }
        if fail { throw Failure.injected }
        return nil
    }
}

private struct Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func manager(validator: @escaping GeoDataManager.Validator = { _, _ in }) -> GeoDataManager {
        GeoDataManager(cacheDirectory: root, validator: validator)
    }
    var source: GeoDataSource { GeoDataSource(provenance: "synthetic test", checksumProvenance: "known test vector", sha256: abcHash) }
    func assertClean() throws {
        let files = FileManager.default.enumerator(atPath: root.path)!.allObjects as! [String]
        #expect(!files.contains { $0.contains(".staging-") })
    }
}

struct BimeronGeoDataTests {
    @Test func knownHashAndImmutableVersions() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let manual = f.root.appendingPathComponent("manual.dat")
        try Data("abc".utf8).write(to: manual)
        let manager = f.manager()
        #expect(try manager.inventory(file: manual, kind: .geoip).sha256 == abcHash)
        let first = try await manager.download(source: f.source, kind: .geoip, transport: Transport([Data("a".utf8), Data("bc".utf8)]))
        #expect(first.byteCount == 3)
        #expect(first.file.path.hasSuffix("\(abcHash)/geoip.dat"))
        let second = try await manager.download(source: f.source, kind: .geoip, transport: Transport([Data("abc".utf8)]))
        #expect(second == first)
        let newHash = "cb8379ac2098aa165029e3938a51da0bcecfc008fd6795f401178647f96c5b34"
        let source = GeoDataSource(provenance: "synthetic", checksumProvenance: "test", sha256: newHash)
        let next = try await manager.download(source: source, kind: .geoip, transport: Transport([Data("def".utf8)]))
        #expect(next.file != first.file)
        #expect(try Data(contentsOf: first.file) == Data("abc".utf8))
        #expect(try Data(contentsOf: manual) == Data("abc".utf8))
        try f.assertClean()
    }

    @Test func rejectsInvalidInputsAndFailures() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let cases: [Transport] = [Transport([]), Transport([Data()]),
            Transport([Data(repeating: 1, count: GeoDataManager.chunkBytes + 1)]),
            Transport([Data("corrupt".utf8)]), Transport([Data("a".utf8)], fail: true)]
        for transport in cases {
            await #expect(throws: (any Error).self) {
                try await f.manager().download(source: f.source, kind: .geosite, transport: transport)
            }
            try f.assertClean()
        }
        await #expect(throws: GeoDataError.invalidSource) {
            try await f.manager().download(source: GeoDataSource(provenance: "", checksumProvenance: "", sha256: "../bad"), kind: .geoip, transport: Transport([]))
        }
    }

    @Test func totalByteBound() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let chunk = Data(repeating: 0, count: GeoDataManager.chunkBytes)
        await #expect(throws: GeoDataError.invalidSize) {
            try await f.manager().download(source: f.source, kind: .geoip,
                transport: Transport(Array(repeating: chunk, count: 1025)))
        }
        try f.assertClean()
    }

    @Test func validatorAndAtomicFailurePreservePriorArtifact() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let first = try await f.manager().download(source: f.source, kind: .geoip, transport: Transport([Data("abc".utf8)]))
        let rejecting = f.manager { file, kind in
            #expect(kind == .geoip)
            #expect(try Data(contentsOf: file) == Data("abc".utf8))
            throw Failure.injected
        }
        var atomicFailure = f.manager()
        atomicFailure.beforePublication = { throw Failure.injected }
        await #expect(throws: Failure.self) {
            try await atomicFailure.download(source: f.source, kind: .geosite, transport: Transport([Data("abc".utf8)]))
        }
        #expect(!FileManager.default.fileExists(atPath: first.file.deletingLastPathComponent().appendingPathComponent("geosite.dat").path))
        for manager in [rejecting, atomicFailure] {
            await #expect(throws: Failure.self) {
                try await manager.download(source: f.source, kind: .geoip, transport: Transport([Data("abc".utf8)]))
            }
            #expect(try Data(contentsOf: first.file) == Data("abc".utf8))
            try f.assertClean()
        }
    }

    @Test func cancellationAtStreamAndCommitBoundaries() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        for beforeCommit in [false, true] {
            let manager = f.manager { _, _ in
                if beforeCommit { withUnsafeCurrentTask { $0?.cancel() } }
            }
            let task = Task {
                try await manager.download(source: f.source, kind: .geoip,
                    transport: Transport([Data("a".utf8), Data("bc".utf8)], cancel: !beforeCommit))
            }
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent(abcHash + "/geoip.dat").path))
            try f.assertClean()
        }
    }

    @Test func rejectsSymlinksAndCorruptExistingArtifact() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let external = f.root.appendingPathComponent("manual")
        try Data("external".utf8).write(to: external)
        let folder = f.root.appendingPathComponent(abcHash)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let final = folder.appendingPathComponent("geoip.dat")
        try FileManager.default.createSymbolicLink(at: final, withDestinationURL: external)
        await #expect(throws: (any Error).self) {
            try await f.manager().download(source: f.source, kind: .geoip, transport: Transport([Data("abc".utf8)]))
        }
        #expect(try Data(contentsOf: external) == Data("external".utf8))
        try FileManager.default.removeItem(at: final)
        try Data("corrupt".utf8).write(to: final)
        await #expect(throws: GeoDataError.checksumMismatch) {
            try await f.manager().download(source: f.source, kind: .geoip, transport: Transport([Data("abc".utf8)]))
        }
        #expect(try Data(contentsOf: final) == Data("corrupt".utf8))
        try f.assertClean()
    }
}
