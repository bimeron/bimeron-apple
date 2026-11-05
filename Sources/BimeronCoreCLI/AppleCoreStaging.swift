import CryptoKit
import Darwin
import Foundation

public enum AppleCoreStagingError: Error {
    case busy, cancelled, invalidFilesystem
    case system(String, Int32)
    /// The named operation remains disposable, untrusted input requiring reconciliation.
    case cleanupIncomplete(operation: String, residual: String, cause: String)
    /// Exclusive publication succeeded, but subsequent confirmation failed. Never retry blindly.
    case publishedButUnconfirmed(AppleCoreStagedCandidate, cause: String)
}

public struct AppleCoreStagedFile: Sendable {
    public let role: AppleCorePayloadRole
    public let count: Int
    public let sha256: String
    public let device: UInt64
    public let inode: UInt64
}

private struct StagingIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
    init(_ info: stat) { device = info.st_dev; inode = info.st_ino }
}

// Internal syscall seams exercise real cleanup and publication under bounded I/O faults.
struct AppleCoreStagingIO {
    var write: (Int32, UnsafeRawPointer, Int) -> Int = { Darwin.write($0, $1, $2) }
    var read: (Int32, UnsafeMutableRawPointer, Int, off_t) -> Int = { pread($0, $1, $2, $3) }
    var closeWriter: (Int32) -> Int32 = { Darwin.close($0) }
    var rename: (Int32, String, String) -> Int32 = { renameatx_np($0, $1, $0, $2, UInt32(RENAME_EXCL)) }
    var checkpoint: (String, Int32) throws -> Void = { _, _ in }
}

/// One active operation per coordinator. The caller must provision and exclusively own the app staging parent.
/// UID/mode checks do not authenticate app identity. Acquisition traverses components without following links.
/// This is disposable, unprivileged storage, never protected Prepared state or runtime readiness.
public final class AppleCoreStagingCoordinator {
    private let parent: Int32
    private let lock = NSLock()
    private let io: AppleCoreStagingIO

    public convenience init(stagingParent: URL) throws {
        try self.init(stagingParent: stagingParent, io: AppleCoreStagingIO())
    }

    init(stagingParent: URL, io: AppleCoreStagingIO) throws {
        parent = try StagingFS.acquireParent(stagingParent)
        self.io = io
    }
    deinit { close(parent) }

    public func stage(_ payload: AppleCoreReleaseVerifiedArchive,
                      cancelled: () -> Bool = { false }) throws -> AppleCoreStagedCandidate {
        guard lock.try() else { throw AppleCoreStagingError.busy }
        defer { lock.unlock() }
        try StagingFS.validate(parent, directory: true)
        let operation = UUID().uuidString.lowercased()
        let temporary = ".incomplete-" + operation
        let publishedName = "candidate-" + operation
        if cancelled() { throw AppleCoreStagingError.cancelled }
        _ = try StagingFS.checked(mkdirat(parent, temporary, 0o700), "mkdirat candidate")
        var directory: Int32 = -1
        var identity: StagingIdentity?
        var handles: [AppleCorePayloadRole: Int32] = [:]
        var identities: [String: StagingIdentity] = [:]
        var records: [AppleCoreStagedFile] = []
        var published = false
        var heldParent: Int32 = -1
        do {
            directory = try StagingFS.checked(openat(parent, temporary, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC), "open candidate")
            identity = StagingIdentity(try StagingFS.info(directory))
            try StagingFS.validate(directory, directory: true)
            try StagingFS.binding(parent, temporary, identity!)
            try io.checkpoint("createdDirectory", directory)
            var total = 0
            for file in payload.files {
                if cancelled() { throw AppleCoreStagingError.cancelled }
                let limit = file.role == .binary ? 268_435_456 : 4_194_304
                let (next, overflow) = total.addingReportingOverflow(file.count)
                guard file.count > 0, file.count <= limit, !overflow, next <= 276_824_064 else {
                    throw AppleCoreStagingError.invalidFilesystem
                }
                total = next
                let name = file.role.rawValue
                let writer = try StagingFS.checked(openat(directory, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600), "create " + name)
                var writerOpen = true
                do {
                    let observed = try StagingFS.info(writer)
                    identities[name] = StagingIdentity(observed)
                    try StagingFS.validate(writer, directory: false)
                    try io.checkpoint("createdFile", writer)
                    try file.contents.withUnsafeBytes { bytes in
                        var offset = 0
                        while offset < bytes.count {
                            if cancelled() { throw AppleCoreStagingError.cancelled }
                            let requested = min(65_536, bytes.count - offset)
                            let n = io.write(writer, bytes.baseAddress!.advanced(by: offset), requested)
                            if n < 0 && errno == EINTR { continue }
                            guard n > 0, n <= requested else { throw AppleCoreStagingError.system("write " + name, n < 0 ? errno : EIO) }
                            offset += n
                        }
                    }
                    try io.checkpoint("wroteFile", writer)
                    try StagingFS.validate(writer, directory: false)
                    guard try StagingFS.info(writer).st_size == file.count else { throw AppleCoreStagingError.invalidFilesystem }
                    try readback(writer, file: file, cancelled: cancelled)
                    let reader = try StagingFS.checked(openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC), "hold " + name)
                    handles[file.role] = reader
                    guard StagingIdentity(try StagingFS.info(reader)) == identities[name] else { throw AppleCoreStagingError.invalidFilesystem }
                    try StagingFS.validate(reader, directory: false)
                    records.append(AppleCoreStagedFile(role: file.role, count: file.count, sha256: file.sha256,
                        device: UInt64(observed.st_dev), inode: UInt64(observed.st_ino)))
                    // close(2) failure leaves descriptor state unspecified: never retry a possibly reused descriptor.
                    writerOpen = false
                    _ = try StagingFS.checked(io.closeWriter(writer), "close " + name)
                } catch {
                    if writerOpen { close(writer) }
                    throw error
                }
            }
            guard records.count == 3 else { throw AppleCoreStagingError.invalidFilesystem }
            try io.checkpoint("beforePublish", directory)
            try StagingFS.validate(parent, directory: true)
            try StagingFS.validate(directory, directory: true)
            try StagingFS.binding(parent, temporary, identity!)
            for file in payload.files {
                let fd = handles[file.role]!
                try StagingFS.validate(fd, directory: false)
                try StagingFS.binding(directory, file.role.rawValue, identities[file.role.rawValue]!)
                guard try StagingFS.info(fd).st_size == file.count else { throw AppleCoreStagingError.invalidFilesystem }
                try readback(fd, file: file, cancelled: cancelled)
            }
            try StagingFS.validateChildren(directory, leaves: identities)
            heldParent = try StagingFS.checked(fcntl(parent, F_DUPFD_CLOEXEC, 0), "hold parent")
            if cancelled() { throw AppleCoreStagingError.cancelled }
            _ = try StagingFS.checked(io.rename(parent, temporary, publishedName), "exclusive publish")
            published = true // Cancellation after this point returns the published candidate.
            let candidate = AppleCoreStagedCandidate(operation: operation, name: publishedName, manifest: payload.manifest,
                files: records, parent: heldParent, directory: directory, identity: identity!, handles: handles, identities: identities)
            directory = -1
            heldParent = -1
            handles = [:]
            do {
                try io.checkpoint("afterPublish", candidate.directoryDescriptor)
                try StagingFS.binding(parent, publishedName, identity!)
                try StagingFS.validate(candidate.directoryDescriptor, directory: true)
            } catch { throw AppleCoreStagingError.publishedButUnconfirmed(candidate, cause: String(describing: error)) }
            return candidate
        } catch {
            if heldParent >= 0 { close(heldParent) }
            if !published {
                do {
                    guard directory >= 0, let identity else { throw AppleCoreStagingError.invalidFilesystem }
                    try StagingFS.cleanup(parent: parent, name: temporary, directory: directory, identity: identity, leaves: identities)
                } catch let cleanupError {
                    for fd in handles.values { close(fd) }
                    if directory >= 0 { close(directory) }
                    throw AppleCoreStagingError.cleanupIncomplete(operation: operation, residual: temporary,
                        cause: "failure: \(error); cleanup: \(cleanupError)")
                }
            }
            for fd in handles.values { close(fd) }
            if directory >= 0 { close(directory) }
            throw error
        }
    }

    private func readback(_ fd: Int32, file: AppleCoreVerifiedFile, cancelled: () -> Bool) throws {
        var buffer = [UInt8](repeating: 0, count: min(65_536, file.count))
        var hash = SHA256()
        try buffer.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < file.count {
                if cancelled() { throw AppleCoreStagingError.cancelled }
                let requested = min(bytes.count, file.count - offset)
                let n = io.read(fd, bytes.baseAddress!, requested, off_t(offset))
                if n < 0 && errno == EINTR { continue }
                guard n > 0, n <= requested else { throw AppleCoreStagingError.system("readback", n < 0 ? errno : EIO) }
                hash.update(bufferPointer: UnsafeRawBufferPointer(start: bytes.baseAddress!, count: n))
                offset += n
            }
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
            throw AppleCoreStagingError.invalidFilesystem
        }
    }
}

/// Handles live until discard or deinit. Deinit closes handles but leaves the disposable artifact intact.
/// A privileged consumer must copy these mutable inodes into protected storage and reverify all evidence there.
public final class AppleCoreStagedCandidate: @unchecked Sendable {
    public let operation: String
    public let name: String
    public let manifest: AppleCoreReleaseManifest
    public let files: [AppleCoreStagedFile]
    private let parent: Int32
    fileprivate let directoryDescriptor: Int32
    private let identity: StagingIdentity
    private let handles: [AppleCorePayloadRole: Int32]
    private let identities: [String: StagingIdentity]
    private let lock = NSLock()
    private var discarded = false

    fileprivate init(operation: String, name: String, manifest: AppleCoreReleaseManifest, files: [AppleCoreStagedFile],
                     parent: Int32, directory: Int32, identity: StagingIdentity,
                     handles: [AppleCorePayloadRole: Int32], identities: [String: StagingIdentity]) {
        self.operation = operation; self.name = name; self.manifest = manifest; self.files = files
        self.parent = parent; directoryDescriptor = directory; self.identity = identity
        self.handles = handles; self.identities = identities
    }
    deinit {
        if !discarded {
            for fd in handles.values { close(fd) }
            close(directoryDescriptor); close(parent)
        }
    }

    /// Borrowed read-only descriptor: the closure must neither close nor retain it.
    public func withFileDescriptor<T>(for role: AppleCorePayloadRole, _ body: (Int32) throws -> T) throws -> T {
        lock.lock()
        guard !discarded, let fd = handles[role] else {
            lock.unlock(); throw AppleCoreStagingError.invalidFilesystem
        }
        let borrowed = fcntl(fd, F_DUPFD_CLOEXEC, 0)
        let savedErrno = errno
        lock.unlock()
        guard borrowed >= 0 else { throw AppleCoreStagingError.system("borrow candidate file", savedErrno) }
        let result: T
        do { result = try body(borrowed) }
        catch { close(borrowed); throw error }
        _ = try StagingFS.checked(close(borrowed), "close borrowed candidate file")
        return result
    }

    /// Deletes only the known identities. A mismatch leaves a named residual for explicit reconciliation.
    public func discard() throws {
        lock.lock(); defer { lock.unlock() }
        if discarded { return }
        do {
            try StagingFS.cleanup(parent: parent, name: name, directory: directoryDescriptor, identity: identity, leaves: identities)
        } catch {
            throw AppleCoreStagingError.cleanupIncomplete(operation: operation, residual: name, cause: String(describing: error))
        }
        discarded = true
        var closeError: Int32?
        for fd in Array(handles.values) + [directoryDescriptor, parent] {
            if close(fd) < 0, closeError == nil { closeError = errno }
        }
        if let closeError { throw AppleCoreStagingError.system("close discarded candidate", closeError) }
    }
}

private enum StagingFS {
    static func checked(_ result: Int32, _ operation: String) throws -> Int32 {
        guard result >= 0 else { throw AppleCoreStagingError.system(operation, errno) }
        return result
    }
    static func info(_ fd: Int32) throws -> stat {
        var result = stat()
        _ = try checked(fstat(fd, &result), "fstat")
        return result
    }
    static func noACL(_ fd: Int32) throws {
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            // Darwin reports ENOENT when this valid inode has no extended ACL.
            if errno == ENOENT { _ = try info(fd); return }
            throw AppleCoreStagingError.system("acl_get_fd_np", errno)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        let result = acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry)
        // Darwin returns -1/EINVAL for an empty ACL, rather than POSIX's zero.
        guard result == -1 && errno == EINVAL else { throw AppleCoreStagingError.invalidFilesystem }
    }
    static func validate(_ fd: Int32, directory: Bool) throws {
        let s = try info(fd)
        guard s.st_uid == geteuid(), s.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
              s.st_mode & 0o7777 == (directory ? 0o700 : 0o600), s.st_flags == 0,
              directory || s.st_nlink == 1 else { throw AppleCoreStagingError.invalidFilesystem }
        try noACL(fd)
    }
    static func binding(_ parent: Int32, _ name: String, _ expected: StagingIdentity) throws {
        var s = stat()
        _ = try checked(fstatat(parent, name, &s, AT_SYMLINK_NOFOLLOW), "identity " + name)
        guard StagingIdentity(s) == expected else { throw AppleCoreStagingError.invalidFilesystem }
    }
    static func acquireParent(_ url: URL) throws -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.utf8.contains(0) else { throw AppleCoreStagingError.invalidFilesystem }
        let components = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty, components.allSatisfy({ $0 != "." && $0 != ".." }) else { throw AppleCoreStagingError.invalidFilesystem }
        var fd = try checked(open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC), "open root")
        do {
            for (index, component) in components.enumerated() {
                let ancestor = try info(fd)
                guard ancestor.st_mode & S_IFMT == S_IFDIR, [uid_t(0), geteuid()].contains(ancestor.st_uid),
                      ancestor.st_mode & 0o022 == 0 || (ancestor.st_uid == 0 && ancestor.st_mode & S_ISVTX != 0)
                else { throw AppleCoreStagingError.invalidFilesystem }
                try noACL(fd)
                let next = try checked(openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC), "open ancestor")
                close(fd); fd = next
                if index == components.count - 1 { try validate(fd, directory: true) }
            }
            return fd
        } catch { close(fd); throw error }
    }
    static func validateChildren(_ directory: Int32, leaves: [String: StagingIdentity]) throws {
        let scanFD = try checked(fcntl(directory, F_DUPFD_CLOEXEC, 0), "duplicate scan")
        guard let scan = fdopendir(scanFD) else { close(scanFD); throw AppleCoreStagingError.system("fdopendir", errno) }
        defer { closedir(scan) }
        rewinddir(scan)
        errno = 0
        while let entry = readdir(scan) {
            let child = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            guard child == "." || child == ".." || leaves[child] != nil else { throw AppleCoreStagingError.invalidFilesystem }
            errno = 0
        }
        guard errno == 0 else { throw AppleCoreStagingError.system("readdir", errno) }
    }
    static func cleanup(parent: Int32, name: String, directory: Int32, identity: StagingIdentity,
                        leaves: [String: StagingIdentity]) throws {
        try binding(parent, name, identity)
        try validate(parent, directory: true)
        try validate(directory, directory: true)
        try validateChildren(directory, leaves: leaves)
        // Preflight every identity before removing any known child.
        for (leaf, expected) in leaves { try binding(directory, leaf, expected) }
        for (leaf, expected) in leaves {
            try binding(parent, name, identity)
            try binding(directory, leaf, expected)
            _ = try checked(unlinkat(directory, leaf, 0), "unlink " + leaf)
        }
        try binding(parent, name, identity)
        _ = try checked(unlinkat(parent, name, AT_REMOVEDIR), "remove candidate")
    }
}
