// Local macOS prototype only. No archive parser, authentication, or payload execution.
// shortcut: ACL/xattr/flags validation, ancestry traversal, hostile same-UID races,
// crash durability, fault injection and privileged intake remain unimplemented.
import Foundation
import CryptoKit
import Darwin

private enum Failure: Error { case rejected, cancelled, system(String, Int32), cleanupIncomplete(String) }
private let leaves = ["bimeron", "LICENSE", "THIRD_PARTY_NOTICES.txt"]
private func owned(_ bytes: Data) -> Data {
    bytes.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
}
private func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
private func require(_ condition: Bool) throws { if !condition { throw Failure.rejected } }
private func checked(_ result: Int32, _ operation: String) throws -> Int32 {
    if result < 0 { throw Failure.system(operation, errno) }; return result
}
private struct Identity: Equatable {
    let device: dev_t; let inode: ino_t
    init(_ s: stat) { device = s.st_dev; inode = s.st_ino }
}
private func info(_ fd: Int32) throws -> stat {
    var s = stat(); _ = try checked(fstat(fd, &s), "fstat"); return s
}
private struct Evidence: Equatable {
    let trust = "SYNTHETIC_UNTRUSTED_MOCK_AUTHENTICATION"
    let manifest: Data; let signature: Data
    let keyID: String; let archiveHash: String; let archiveSize: Int
    let architecture: String; let version: String; let revision: String
    let compatibility: String; let approval: String; let policy: String; let context: String
}
private struct Payload {
    let contents: [Data]; let evidence: Evidence; let hashes: [String]
    private init(_ contents: [Data], _ evidence: Evidence) {
        self.contents = contents; self.evidence = evidence; hashes = contents.map(digest)
    }
    // Models the complete gate's final return, never a partially successful entry loop.
    static func syntheticGate(_ decoded: [Data], completeArchive: Bool = true,
                              declaredCounts: [Int]? = nil, totalLimit: Int = 276_824_064) throws -> Payload {
        try require(completeArchive && decoded.count == 3)
        let counts = declaredCounts ?? decoded.map(\.count)
        try require(counts.count == 3)
        var total = 0
        for i in 0..<3 {
            let limit = i == 0 ? 268_435_456 : 4_194_304
            try require(counts[i] > 0 && counts[i] <= limit && decoded[i].count == counts[i])
            let (next, overflow) = total.addingReportingOverflow(counts[i])
            try require(!overflow && next <= totalLimit); total = next
        }
        let snapshot = decoded.map(owned)
        let evidence = Evidence(manifest: Data("mock manifest: complete three-entry fixture".utf8),
            signature: Data("NOT A VALID SIGNATURE".utf8), keyID: "mock-key", archiveHash: digest(Data("synthetic archive identity only".utf8)),
            archiveSize: 31, architecture: "arm64", version: "0.0.0", revision: "synthetic",
            compatibility: "mock-only", approval: "none", policy: "prototype-v1", context: "offline-test")
        return Payload(snapshot, evidence)
    }
}
private struct Candidate {
    let operation: String; let evidence: Evidence; let counts: [Int]; let hashes: [String]
    private init(_ operation: String, _ payload: Payload) {
        self.operation = operation; evidence = payload.evidence
        counts = payload.contents.map(\.count); hashes = payload.hashes
    }
    static func stage(_ payload: Payload, parent: Int32, target: String,
                      cancelled: () -> Bool = { false }, afterPublish: () -> Void = {}) throws -> Candidate {
        try require(!target.isEmpty && !target.contains("/") && target != "." && target != ".." && !target.utf8.contains(0))
        let parentInfo = try info(parent)
        try require(parentInfo.st_uid == geteuid() && parentInfo.st_mode & 0o777 == 0o700 && parentInfo.st_mode & S_IFMT == S_IFDIR)
        let temporary = ".incomplete-" + UUID().uuidString
        _ = try checked(mkdirat(parent, temporary, 0o700), "mkdirat")
        let directory: Int32
        do { directory = try checked(openat(parent, temporary, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC), "openat directory") }
        catch { throw Failure.cleanupIncomplete(temporary) }
        defer { close(directory) }
        let identity: Identity
        do { identity = Identity(try info(directory)) }
        catch { throw Failure.cleanupIncomplete(temporary) }
        var created: [String: Identity] = [:]
        var published = false
        do {
            let ds = try info(directory)
            try require(ds.st_uid == geteuid() && ds.st_mode & 0o777 == 0o700 && ds.st_mode & S_IFMT == S_IFDIR)
            for i in 0..<3 {
                if cancelled() { throw Failure.cancelled }
                let fd = try checked(openat(directory, leaves[i], O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600), "create leaf")
                do {
                    let s = try info(fd); created[leaves[i]] = Identity(s)
                    try require(s.st_uid == geteuid() && s.st_nlink == 1 && s.st_mode & S_IFMT == S_IFREG && s.st_mode & 0o777 == 0o600)
                    try payload.contents[i].withUnsafeBytes { bytes in
                        var offset = 0
                        while offset < bytes.count {
                            if cancelled() { throw Failure.cancelled }
                            let count = min(65_536, bytes.count - offset)
                            let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), count)
                            if n < 0 && errno == EINTR { continue }
                            if n <= 0 { throw Failure.system("write", errno) }
                            offset += n
                        }
                    }
                    try require(Int(try info(fd).st_size) == payload.contents[i].count)
                    var readback = Data(count: min(65_536, payload.contents[i].count))
                    var hasher = SHA256()
                    try readback.withUnsafeMutableBytes { bytes in
                        var offset = 0
                        while offset < payload.contents[i].count {
                            if cancelled() { throw Failure.cancelled }
                            let requested = min(bytes.count, payload.contents[i].count - offset)
                            let n = pread(fd, bytes.baseAddress!, requested, off_t(offset))
                            if n < 0 && errno == EINTR { continue }
                            if n <= 0 { throw Failure.system("readback", errno) }
                            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: bytes.baseAddress!, count: n))
                            offset += n
                        }
                    }
                    let actualHash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    try require(actualHash == payload.hashes[i])
                } catch { close(fd); throw error }
                _ = try checked(close(fd), "close leaf")
            }
            if cancelled() { throw Failure.cancelled }
            _ = try checked(renameatx_np(parent, temporary, parent, target, UInt32(RENAME_EXCL)), "exclusive publish")
            published = true // Linearization point: later cancellation returns success.
            afterPublish()
            return Candidate(target, payload)
        } catch {
            if !published {
                do { try cleanup(parent: parent, name: temporary, directory: directory, identity: identity, leaves: created) }
                catch { throw Failure.cleanupIncomplete(temporary) }
            }
            throw error
        }
    }
}
// Only known leaves, checked relative to held handles; unexpected children leave a residual.
private func cleanup(parent: Int32, name: String, directory: Int32, identity: Identity,
                     leaves known: [String: Identity]) throws {
    var s = stat()
    _ = try checked(fstatat(parent, name, &s, AT_SYMLINK_NOFOLLOW), "cleanup directory identity")
    try require(Identity(s) == identity && s.st_mode & S_IFMT == S_IFDIR)
    let scanFD = try checked(dup(directory), "cleanup dup")
    guard let scan = fdopendir(scanFD) else { close(scanFD); throw Failure.cleanupIncomplete(name) }
    defer { closedir(scan) }
    errno = 0
    while let entry = readdir(scan) {
        let name = withUnsafePointer(to: &entry.pointee.d_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
        }
        if name != "." && name != ".." && known[name] == nil { throw Failure.cleanupIncomplete(name) }
        errno = 0
    }
    if errno != 0 { throw Failure.cleanupIncomplete(name) }
    for (leaf, expected) in known {
        _ = try checked(fstatat(directory, leaf, &s, AT_SYMLINK_NOFOLLOW), "cleanup leaf identity")
        try require(Identity(s) == expected && s.st_mode & S_IFMT == S_IFREG)
        _ = try checked(unlinkat(directory, leaf, 0), "unlink leaf")
    }
    _ = try checked(unlinkat(parent, name, AT_REMOVEDIR), "remove empty directory")
}

private func expectFailure(_ body: () throws -> Void) {
    do { try body(); assertionFailure("Expected rejection") } catch { }
}
private func runTests() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("staging-prototype-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let parent = try checked(open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC), "test parent")
    defer { close(parent); try? FileManager.default.removeItem(at: root) } // Test-owned temp fixtures only.
    let fixtures = [Data(repeating: 0x51, count: 131_073), Data("license".utf8), Data("notices".utf8)]
    let payload = try Payload.syntheticGate(fixtures)
    expectFailure { _ = try Payload.syntheticGate(fixtures, completeArchive: false) }
    expectFailure { _ = try Payload.syntheticGate(Array(fixtures.prefix(2))) }
    expectFailure { _ = try Payload.syntheticGate(fixtures, declaredCounts: [1, 7, 7]) }
    expectFailure { _ = try Payload.syntheticGate(fixtures, totalLimit: 1) }
    expectFailure { _ = try Payload.syntheticGate(fixtures, declaredCounts: [268_435_457, 7, 7]) }
    let backing = NSMutableData(data: fixtures[0])
    let external = Data(referencing: backing)
    let copied = try Payload.syntheticGate([external, fixtures[1], fixtures[2]])
    memset(backing.mutableBytes, 88, backing.length)
    assert(copied.contents[0] == fixtures[0])
    var cancelled = false
    let candidate = try Candidate.stage(payload, parent: parent, target: "success", cancelled: { cancelled }, afterPublish: { cancelled = true })
    assert(cancelled && candidate.operation == "success" && candidate.evidence == payload.evidence)
    assert(candidate.evidence.trust.contains("UNTRUSTED") && !candidate.evidence.signature.isEmpty)
    assert(candidate.counts == fixtures.map(\.count) && candidate.hashes == fixtures.map(digest))
    for i in 0..<3 {
        let url = root.appendingPathComponent("success/" + leaves[i])
        let actual = try Data(contentsOf: url)
        assert(actual == fixtures[i])
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        assert((attributes[.posixPermissions] as! NSNumber).intValue == 0o600)
    }
    expectFailure { _ = try Candidate.stage(payload, parent: parent, target: "cancelled", cancelled: { true }) }
    var polls = 0
    expectFailure { _ = try Candidate.stage(payload, parent: parent, target: "mid-cancel", cancelled: { polls += 1; return polls == 3 }) }
    let before = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("success").path)[.systemFileNumber] as! NSNumber
    expectFailure { _ = try Candidate.stage(payload, parent: parent, target: "success") }
    let after = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("success").path)[.systemFileNumber] as! NSNumber
    assert(before == after)
    let preserved = try Data(contentsOf: root.appendingPathComponent("success/bimeron"))
    assert(preserved == fixtures[0])
    let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
    assert(remaining == ["success"])
    // Unknown children stop removal; cleanup never recursively removes them.
    _ = try checked(mkdirat(parent, "residual", 0o700), "fixture directory")
    let dir = try checked(openat(parent, "residual", O_RDONLY | O_DIRECTORY | O_NOFOLLOW), "fixture open")
    let unknown = try checked(openat(dir, "unknown", O_CREAT | O_EXCL | O_WRONLY, 0o600), "fixture unknown")
    close(unknown)
    expectFailure { try cleanup(parent: parent, name: "residual", directory: dir, identity: Identity(try info(dir)), leaves: [:]) }
    assert(faccessat(dir, "unknown", F_OK, 0) == 0)
    close(dir)
    print("PASS: success; incomplete archive/count/quota rejection; external NSData ownership; cancellation before/during/after publish; exclusive collision preserves target; known-leaf cleanup; unknown residual preservation; full mock evidence retention")
}
try runTests()
