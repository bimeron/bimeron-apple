import CryptoKit
import Darwin
import Foundation
import Testing
@testable import BimeronGeoData

private enum LocalFailure: Error { case rejected }

private struct LocalFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var input: URL { root.appendingPathComponent("input") }
    var cache: URL { root.appendingPathComponent("cache") }
    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func source(_ data: Data) -> GeoDataSource {
        GeoDataSource(provenance: "caller supplied synthetic bytes",
                      checksumProvenance: "synthetic test digest",
                      sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }
    func assertClean() throws {
        let paths = FileManager.default.enumerator(atPath: cache.path)!.allObjects as! [String]
        #expect(!paths.contains { $0.contains(".staging-") })
    }
}

struct LocalGeoDataTests {
    @Test func importsThroughValidatorAndPreservesInput() async throws {
        let f = try LocalFixture(); defer { f.cleanup() }
        let bytes = Data(repeating: 42, count: GeoDataManager.chunkBytes + 17)
        try bytes.write(to: f.input)
        let manager = GeoDataManager(cacheDirectory: f.cache) { file, kind in
            #expect(kind == .geosite)
            #expect(file != f.input)
            let stagedBytes = try Data(contentsOf: file)
            #expect(stagedBytes == bytes)
        }
        let result = try await manager.importLocalFile(f.input, source: f.source(bytes), kind: .geosite)
        #expect(result.byteCount == bytes.count)
        #expect(try Data(contentsOf: result.file) == bytes)
        #expect(try Data(contentsOf: f.input) == bytes)
        #expect(try await manager.importLocalFile(f.input, source: f.source(bytes), kind: .geosite) == result)
        try f.assertClean()
    }

    @Test func boundedChunksAndStableOpenedFile() async throws {
        let f = try LocalFixture(); defer { f.cleanup() }
        try Data("abc".utf8).write(to: f.input)
        let transport = try LocalGeoDataTransport(file: f.input)
        try FileManager.default.removeItem(at: f.input)
        try Data("replacement".utf8).write(to: f.input)
        #expect(try await transport.nextChunk(maxBytes: 1) == Data("a".utf8))
        #expect(try await transport.nextChunk(maxBytes: Int.max) == Data("bc".utf8))
        #expect(try await transport.nextChunk(maxBytes: 1) == nil)
        await transport.close()
        #expect(try await transport.nextChunk(maxBytes: 1) == nil)
    }

    @Test func rejectsUnsafeInputsAndOversize() async throws {
        let f = try LocalFixture(); defer { f.cleanup() }
        try Data("abc".utf8).write(to: f.input)
        let link = f.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.input)
        let fifo = f.root.appendingPathComponent("fifo")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        for file in [link, fifo, f.cache, f.root.appendingPathComponent("missing")] {
            #expect(throws: (any Error).self) { try LocalGeoDataTransport(file: file) }
        }
        let handle = try FileHandle(forWritingTo: f.input)
        try handle.truncate(atOffset: UInt64(GeoDataManager.maximumBytes + 1))
        try handle.close()
        #expect(throws: GeoDataError.invalidSize) { try LocalGeoDataTransport(file: f.input) }
    }

    @Test func detectsGrowthBeyondTotalBound() async throws {
        let f = try LocalFixture(); defer { f.cleanup() }
        try Data().write(to: f.input)
        let transport = try LocalGeoDataTransport(file: f.input)
        let handle = try FileHandle(forWritingTo: f.input)
        try handle.truncate(atOffset: UInt64(GeoDataManager.maximumBytes + 1))
        try handle.close()
        await #expect(throws: GeoDataError.invalidSize) {
            while let chunk = try await transport.nextChunk(maxBytes: Int.max) {
                #expect(chunk.count <= GeoDataManager.chunkBytes)
            }
        }
        #expect(try await transport.nextChunk(maxBytes: 1) == nil)
    }

    @Test func failuresCleanStagingAndNeverClobber() async throws {
        let f = try LocalFixture(); defer { f.cleanup() }
        let bytes = Data("abc".utf8)
        try bytes.write(to: f.input)
        let source = f.source(bytes)
        let manager = GeoDataManager(cacheDirectory: f.cache) { _, _ in }
        let rejecting = GeoDataManager(cacheDirectory: f.cache) { _, _ in throw LocalFailure.rejected }
        await #expect(throws: LocalFailure.self) {
            try await rejecting.importLocalFile(f.input, source: source, kind: .geoip)
        }
        await #expect(throws: GeoDataError.checksumMismatch) {
            try await manager.importLocalFile(f.input, source: f.source(Data("other".utf8)), kind: .geoip)
        }
        await #expect(throws: GeoDataError.invalidSource) {
            try await manager.importLocalFile(f.input,
                source: GeoDataSource(provenance: "", checksumProvenance: "", sha256: source.sha256), kind: .geoip)
        }
        let destination = f.cache.appendingPathComponent(source.sha256).appendingPathComponent("geoip.dat")
        try Data("existing".utf8).write(to: destination)
        await #expect(throws: GeoDataError.checksumMismatch) {
            try await manager.importLocalFile(f.input, source: source, kind: .geoip)
        }
        #expect(try Data(contentsOf: destination) == Data("existing".utf8))
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: f.input)
        await #expect(throws: (any Error).self) {
            try await manager.importLocalFile(f.input, source: source, kind: .geoip)
        }
        try FileManager.default.removeItem(at: destination)
        #expect(mkfifo(destination.path, 0o600) == 0)
        await #expect(throws: GeoDataError.unsafeFile) {
            try await manager.importLocalFile(f.input, source: source, kind: .geoip)
        }
        #expect(try Data(contentsOf: f.input) == bytes)
        try f.assertClean()
    }

    @Test func rejectsEmptyFileAndInvalidChunkRequest() async throws {
        let f = try LocalFixture(); defer { f.cleanup() }
        try Data().write(to: f.input)
        let manager = GeoDataManager(cacheDirectory: f.cache) { _, _ in
            Issue.record("Empty bytes must not reach the validator")
        }
        await #expect(throws: GeoDataError.invalidSize) {
            try await manager.importLocalFile(f.input, source: f.source(Data()), kind: .geoip)
        }
        let transport = try LocalGeoDataTransport(file: f.input)
        await #expect(throws: GeoDataError.invalidSize) { try await transport.nextChunk(maxBytes: 0) }
        #expect(try await transport.nextChunk(maxBytes: 1) == nil)
        try f.assertClean()
    }

    @Test func cancellationClosesStreamAndCleansImport() async throws {
        let f = try LocalFixture(); defer { f.cleanup() }
        let bytes = Data("abc".utf8)
        try bytes.write(to: f.input)
        let transport = try LocalGeoDataTransport(file: f.input)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.nextChunk(maxBytes: 1)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await transport.nextChunk(maxBytes: 1) == nil)
        let manager = GeoDataManager(cacheDirectory: f.cache) { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let importing = Task { try await manager.importLocalFile(f.input, source: f.source(bytes), kind: .geoip) }
        await #expect(throws: CancellationError.self) { try await importing.value }
        #expect(!FileManager.default.fileExists(atPath: f.cache.appendingPathComponent(f.source(bytes).sha256 + "/geoip.dat").path))
        try f.assertClean()
    }
}
