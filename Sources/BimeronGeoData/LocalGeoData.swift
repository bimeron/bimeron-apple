import Darwin
import Foundation

/// A single bounded stream from an opened regular file; the path conveys no trust.
public actor LocalGeoDataTransport: GeoDataTransport {
    private var descriptor: Int32?
    private var byteCount = 0

    public init(file: URL) throws {
        try Task.checkCancellation()
        guard file.isFileURL else { throw GeoDataError.unsafeFile }
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw GeoDataError.fileSystem(errno) }
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            let error = errno
            Darwin.close(fd)
            throw GeoDataError.fileSystem(error)
        }
        guard info.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(fd)
            throw GeoDataError.unsafeFile
        }
        guard info.st_size <= GeoDataManager.maximumBytes else {
            Darwin.close(fd)
            throw GeoDataError.invalidSize
        }
        descriptor = fd
    }

    deinit {
        if let descriptor { Darwin.close(descriptor) }
    }

    public func nextChunk(maxBytes: Int) async throws -> Data? {
        do {
            try Task.checkCancellation()
            guard maxBytes > 0 else { throw GeoDataError.invalidSize }
            guard let descriptor else { return nil }
            var buffer = [UInt8](repeating: 0, count: min(maxBytes, GeoDataManager.chunkBytes))
            var count: Int
            repeat {
                try Task.checkCancellation()
                count = read(descriptor, &buffer, buffer.count)
            } while count < 0 && errno == EINTR
            guard count >= 0 else { throw GeoDataError.fileSystem(errno) }
            try Task.checkCancellation()
            if count == 0 { close(); return nil }
            guard count <= GeoDataManager.maximumBytes - byteCount else {
                throw GeoDataError.invalidSize
            }
            byteCount += count
            return Data(buffer.prefix(count))
        } catch {
            close()
            throw error
        }
    }

    /// Releases the descriptor even when a consumer stops before EOF.
    public func close() {
        if let descriptor { Darwin.close(descriptor) }
        descriptor = nil
    }
}

extension GeoDataManager {
    /// Imports through the same checksum, mandatory validator and no-clobber publication flow.
    /// Kind, source and checksum provenance are caller assertions; neither a local path nor
    /// a matching hash establishes authenticity or semantic validity. The validator decides validity.
    public func importLocalFile(_ file: URL, source: GeoDataSource,
                                kind: GeoDataKind) async throws -> GeoDataInventory {
        let transport = try LocalGeoDataTransport(file: file)
        do {
            let result = try await download(source: source, kind: kind, transport: transport)
            await transport.close()
            return result
        } catch {
            await transport.close()
            throw error
        }
    }
}
