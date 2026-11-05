import CryptoKit
import Darwin
import Foundation

public enum GeoDataKind: String, Sendable { case geoip, geosite }

public struct GeoDataInventory: Sendable, Equatable {
    public let file: URL
    public let kind: GeoDataKind
    public let sha256: String
    public let byteCount: Int
}

/// Caller assertions, not independently authenticated provider metadata.
public struct GeoDataSource: Sendable {
    public let provenance: String
    public let checksumProvenance: String
    public let sha256: String

    public init(provenance: String, checksumProvenance: String, sha256: String) {
        self.provenance = provenance
        self.checksumProvenance = checksumProvenance
        self.sha256 = sha256
    }
}

/// Implementations must produce at most maxBytes per call, avoid unbounded buffering,
/// and cooperate with task cancellation. nil denotes EOF; empty chunks are invalid.
public protocol GeoDataTransport: Sendable {
    func nextChunk(maxBytes: Int) async throws -> Data?
}

public enum GeoDataError: Error, Equatable {
    case invalidSource, invalidSize, checksumMismatch, unsafeFile
    case fileSystem(Int32)
}

public struct GeoDataManager: Sendable {
    public static let maximumBytes = 64 * 1024 * 1024
    public static let chunkBytes = 64 * 1024
    public typealias Validator = @Sendable (URL, GeoDataKind) async throws -> Void

    private let cacheDirectory: URL
    private let validator: Validator
    // Internal fault seam exercises publication failures without replacing filesystem policy.
    var beforePublication: @Sendable () throws -> Void = {}

    public init(cacheDirectory: URL, validator: @escaping Validator) {
        self.cacheDirectory = cacheDirectory
        self.validator = validator
    }

    /// Hashes a regular local file read-only; this does not validate its GeoData semantics.
    public func inventory(file: URL, kind: GeoDataKind) throws -> GeoDataInventory {
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw GeoDataError.fileSystem(errno) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw GeoDataError.fileSystem(errno) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw GeoDataError.unsafeFile }
        var hash = SHA256()
        var count = 0
        var buffer = [UInt8](repeating: 0, count: Self.chunkBytes)
        while true {
            try Task.checkCancellation()
            let n = read(fd, &buffer, buffer.count)
            guard n >= 0 else { throw GeoDataError.fileSystem(errno) }
            if n == 0 { break }
            count += n
            guard count <= Self.maximumBytes else { throw GeoDataError.invalidSize }
            hash.update(data: Data(buffer.prefix(n)))
        }
        guard count > 0 else { throw GeoDataError.invalidSize }
        return GeoDataInventory(file: file, kind: kind, sha256: Self.hex(hash.finalize()), byteCount: count)
    }

    public func download(source: GeoDataSource, kind: GeoDataKind,
                         transport: any GeoDataTransport) async throws -> GeoDataInventory {
        guard !source.provenance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !source.checksumProvenance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              source.sha256.count == 64,
              source.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { throw GeoDataError.invalidSource }
        try Task.checkCancellation()
        let root = open(cacheDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard root >= 0 else { throw GeoDataError.fileSystem(errno) }
        defer { close(root) }
        if mkdirat(root, source.sha256, 0o700) != 0 && errno != EEXIST {
            throw GeoDataError.fileSystem(errno)
        }
        let directory = openat(root, source.sha256, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw GeoDataError.fileSystem(errno) }
        defer { close(directory) }
        let name = kind.rawValue + ".dat"
        let staging = ".staging-" + UUID().uuidString
        let fd = openat(directory, staging, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw GeoDataError.fileSystem(errno) }
        defer { close(fd); unlinkat(directory, staging, 0) }
        let folder = cacheDirectory.appendingPathComponent(source.sha256, isDirectory: true)
        let stagedURL = folder.appendingPathComponent(staging)
        let destination = folder.appendingPathComponent(name)
        var count = 0
        while let chunk = try await transport.nextChunk(maxBytes: Self.chunkBytes) {
            try Task.checkCancellation()
            guard !chunk.isEmpty, chunk.count <= Self.chunkBytes,
                  chunk.count <= Self.maximumBytes - count else { throw GeoDataError.invalidSize }
            try chunk.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let written = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    guard written > 0 else { throw GeoDataError.fileSystem(errno) }
                    offset += written
                }
            }
            count += chunk.count
        }
        guard count > 0 else { throw GeoDataError.invalidSize }
        guard try inventory(file: stagedURL, kind: kind).sha256 == source.sha256 else {
            throw GeoDataError.checksumMismatch
        }
        try Task.checkCancellation()
        try await validator(stagedURL, kind)
        // A validator is trusted code, but must not accidentally change the published bytes.
        let checked = try inventory(file: stagedURL, kind: kind)
        guard checked.sha256 == source.sha256 else { throw GeoDataError.checksumMismatch }
        guard fsync(fd) == 0 else { throw GeoDataError.fileSystem(errno) }
        try beforePublication()
        try Task.checkCancellation()
        // linkat atomically publishes without ever replacing an existing path or following it.
        if linkat(directory, staging, directory, name, 0) != 0 {
            guard errno == EEXIST else { throw GeoDataError.fileSystem(errno) }
            guard try inventory(file: destination, kind: kind).sha256 == source.sha256 else {
                throw GeoDataError.checksumMismatch
            }
        }
        return GeoDataInventory(file: destination, kind: kind, sha256: checked.sha256, byteCount: checked.byteCount)
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
