import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import BimeronCoreCLI

/// Signed synthetic Mach-O/Go records, never an executable or release candidate.
struct StagingFixture {
    static let revision = String(repeating: "1", count: 40)
    static let version = "0.1.0-beta.1"
    let archive: Data
    let manifest: Data
    let signature: Data
    let key: Curve25519.Signing.PrivateKey
    let decoded: [Data]

    init(architecture: String = "arm64", notice: Data = Data("notice".utf8), localName: String? = nil, binaryPadding: Int = 0) throws {
        key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0, count: 32))
        decoded = [Self.binary(architecture) + Data(repeating: 0, count: binaryPadding), Data("license".utf8), notice]
        archive = Self.zip(decoded, architecture: architecture, localName: localName)
        let hash = AppleCoreRelease.digest(archive)
        let archiveCount = archive.count
        let object: [String: Any] = ["schema": 1, "product": "bimeron-apple-core", "tag": "v" + Self.version,
            "core_version": Self.version, "channel": "beta", "source_revision": Self.revision,
            "key_id": "139e3940e64b5491",
            "compatibility": ["schema": 1, "app_min": "0.1.0", "app_max_exclusive": "0.1.1", "apple_reviewed": true,
                "ipc_min": 1, "ipc_max": 1, "profile_format": 1, "daemon_session_guards": true],
            "archives": ["arm64", "amd64"].map { arch in ["os": "macos", "arch": arch,
                "name": "bimeron-v\(Self.version)-macos-\(arch).zip", "size": archiveCount, "sha256": hash] as [String: Any] }]
        manifest = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data([10])
        signature = Data((try key.signature(for: manifest).base64EncodedString() + "\n").utf8)
    }
    func descriptor(_ bytes: Data? = nil, architecture: String = "arm64", context: AppleCoreVerificationContext? = nil) throws -> AppleCoreReleaseManifest {
        try AppleCoreRelease.verifyManifest(bytes ?? manifest, signature: signature, trustedPublicKey: key.publicKey.rawRepresentation,
            approval: .init(tag: "v" + Self.version, sourceRevision: Self.revision), appVersion: "0.1.0", channel: "beta", architecture: architecture,
            context: context ?? .init(classification: .syntheticUntrusted, approvalIdentity: "synthetic fixture only",
                pinProvenance: "deterministic test key; no production pin", appleBuildIdentity: "unit test"))
    }
    func payload(architecture: String = "arm64") throws -> AppleCoreReleaseVerifiedArchive {
        try AppleCoreRelease.verifyArchive(archive, manifest: descriptor(architecture: architecture))
    }
    private static func number(_ n: UInt64, _ size: Int) -> Data { Data((0..<size).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) }) }
    private static func name(_ value: String) -> Data { Data(value.utf8) + Data(repeating: 0, count: 16 - value.utf8.count) }
    private static func varint(_ value: Int) -> Data {
        var n = value, result = Data()
        repeat { let b = UInt8(n & 127); n >>= 7; result.append(b | (n > 0 ? 128 : 0)) } while n > 0
        return result
    }
    static func binary(_ architecture: String) -> Data {
        let record = Data(("BIMERON.APPLE.CORE.VERSION/v1\0" + String(format: "%03d", version.utf8.count) + ":" + version + "\0END.APPLE.CORE.RECORD/v1\0").utf8)
        let module = Data(("build\tGOOS=darwin\nbuild\tGOARCH=\(architecture)\nbuild\tvcs=git\nbuild\tvcs.revision=\(revision)\nbuild\tvcs.modified=false\nbuild\t-trimpath=true\n").utf8)
        let framed = Data(repeating: 1, count: 16) + module + Data(repeating: 2, count: 16)
        let go = Data([255]) + Data(" Go buildinf:".utf8) + Data([8, 2]) + Data(repeating: 0, count: 16)
            + varint(6) + Data("go1.26".utf8) + varint(framed.count) + framed
        let commandSize = 232, offset = 32 + commandSize, size = offset + record.count + go.count
        var header = number(0xfeedfacf, 4) + number(architecture == "arm64" ? 0x100000c : 0x1000007, 4)
        header += number(0, 4) + number(2, 4) + number(1, 4) + number(UInt64(commandSize), 4) + number(0, 8)
        var segment = number(0x19, 4) + number(UInt64(commandSize), 4) + name("__TEXT")
        segment += number(0x1000, 8) + number(UInt64(size), 8) + number(0, 8) + number(UInt64(size), 8)
        segment += number(5, 4) + number(5, 4) + number(2, 4) + number(0, 4)
        for (section, start, count) in [("__rodata", offset, record.count), ("__go_buildinfo", offset + record.count, go.count)] {
            segment += name(section) + name("__TEXT") + number(UInt64(0x1000 + start), 8) + number(UInt64(count), 8)
            segment += number(UInt64(start), 4) + Data(repeating: 0, count: 28)
        }
        return header + segment + record + go
    }
    static func zip(_ contents: [Data], architecture: String, localName: String? = nil) -> Data {
        var body = Data(), central = Data()
        for (index, data) in contents.enumerated() {
            let path = Data("macos-\(architecture)/\(AppleCorePayloadRole.allCases[index].rawValue)".utf8)
            let local = localName.map { Data($0.utf8) } ?? path
            let offset = body.count
            body += number(0x04034b50, 4) + number(20, 2) + Data(repeating: 0, count: 8)
            body += number(0, 4) + number(UInt64(data.count), 4) + number(UInt64(data.count), 4)
            body += number(UInt64(local.count), 2) + number(0, 2) + local + data
            central += number(0x02014b50, 4) + number(0x0314, 2) + number(20, 2) + Data(repeating: 0, count: 8)
            central += number(0, 4) + number(UInt64(data.count), 4) + number(UInt64(data.count), 4)
            central += number(UInt64(path.count), 2) + Data(repeating: 0, count: 8)
            central += number(UInt64((index == 0 ? 0o100755 : 0o100644) << 16), 4) + number(UInt64(offset), 4) + path
        }
        return body + central + number(0x06054b50, 4) + number(0, 4) + number(UInt64(contents.count), 2)
            + number(UInt64(contents.count), 2) + number(UInt64(central.count), 4) + number(UInt64(body.count), 4) + number(0, 2)
    }
}

final class AppleCoreStagingTests: XCTestCase {
    private func root() throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp/bimeron-stage-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try? FileManager.default.removeItem(at: url) } // Only test-created disposable fixtures.
        return url
    }
    private func children(_ root: URL) throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() }
    func testWholeAuthenticatedPayloadAndOriginalEvidence() throws {
        for architecture in ["arm64", "amd64"] {
            let fixture = try StagingFixture(architecture: architecture, localName: "../../ignored-local-name")
            let payload = try fixture.payload(architecture: architecture)
            XCTAssertEqual(payload.files.map(\.role), AppleCorePayloadRole.allCases)
            XCTAssertEqual(payload.files.map(\.contents), fixture.decoded)
            XCTAssertEqual(payload.files.map(\.sha256), fixture.decoded.map(AppleCoreRelease.digest))
            XCTAssertEqual(payload.manifest.evidence.signedManifest, fixture.manifest)
            XCTAssertEqual(payload.manifest.evidence.signature, fixture.signature)
            XCTAssertEqual(payload.manifest.evidence.context.classification, .syntheticUntrusted)
            XCTAssertEqual(payload.manifest.architecture, architecture)
        }
        let broken = try StagingFixture(notice: Data())
        XCTAssertThrowsError(try broken.payload()) // Valid binary and license cannot produce partial success.
    }
    func testExternalManifestAndArchiveAliasesDetachBeforeAuthentication() throws {
        let fixture = try StagingFixture()
        func external(_ original: Data) -> (NSMutableData, Data) {
            let backing = NSMutableData(data: original)
            let bytes = Data(bytesNoCopy: backing.mutableBytes, count: backing.length, deallocator: .none)
            let saved = backing.mutableBytes.load(as: UInt8.self)
            backing.mutableBytes.storeBytes(of: saved ^ 255, as: UInt8.self)
            XCTAssertEqual(bytes.first, saved ^ 255, "Fixture must actually alias externally writable memory")
            backing.mutableBytes.storeBytes(of: saved, as: UInt8.self)
            XCTAssertEqual(bytes, original)
            return (backing, bytes)
        }
        let (manifestBacking, manifestBytes) = external(fixture.manifest)
        let (signatureBacking, signatureBytes) = external(fixture.signature)
        let (keyBacking, keyBytes) = external(fixture.key.publicKey.rawRepresentation)
        let context = AppleCoreVerificationContext(classification: .syntheticUntrusted,
            approvalIdentity: "test", pinProvenance: "test", appleBuildIdentity: "test")
        let descriptor = try AppleCoreRelease.verifyManifestSnapshot(manifestBytes, signature: signatureBytes,
            trustedPublicKey: keyBytes, approval: .init(tag: "v" + StagingFixture.version, sourceRevision: StagingFixture.revision),
            appVersion: "0.1.0", channel: "beta", architecture: "arm64", context: context, afterSnapshot: {
                memset(manifestBacking.mutableBytes, 0, manifestBacking.length)
                memset(signatureBacking.mutableBytes, 0, signatureBacking.length)
                memset(keyBacking.mutableBytes, 0, keyBacking.length)
            })
        XCTAssertEqual(descriptor.evidence.signedManifest, fixture.manifest)
        XCTAssertEqual(descriptor.evidence.signature, fixture.signature)
        XCTAssertEqual(descriptor.evidence.publicKey, fixture.key.publicKey.rawRepresentation)
        let (archiveBacking, archive) = external(fixture.archive)
        let payload = try AppleCoreRelease.verifyArchiveSnapshot(archive, manifest: descriptor, afterSnapshot: {
            memset(archiveBacking.mutableBytes, 0, archiveBacking.length)
        })
        XCTAssertEqual(payload.files.map(\.contents), fixture.decoded)
        XCTAssertEqual(payload.manifest.evidence.signedManifest, fixture.manifest)
        XCTAssertThrowsError(try fixture.descriptor(context: .init(classification: .syntheticUntrusted,
            approvalIdentity: String(repeating: "x", count: 1025), pinProvenance: "", appleBuildIdentity: "")))
    }
    func testPrivateFixedOutputsHeldHandlesAndDeterministicDiscard() throws {
        let root = try root(), fixture = try StagingFixture()
        var coordinator: AppleCoreStagingCoordinator? = try .init(stagingParent: root)
        let candidate = try coordinator!.stage(fixture.payload())
        coordinator = nil
        XCTAssertEqual(candidate.manifest.evidence.signedManifest, fixture.manifest)
        XCTAssertEqual(candidate.manifest.evidence.signature, fixture.signature)
        XCTAssertEqual(candidate.manifest.evidence.context.classification, .syntheticUntrusted)
        XCTAssertEqual(candidate.files.map(\.sha256), fixture.decoded.map(AppleCoreRelease.digest))
        XCTAssertEqual(try children(root), [candidate.name])
        let directory = root.appendingPathComponent(candidate.name)
        XCTAssertEqual(try children(directory), AppleCorePayloadRole.allCases.map(\.rawValue).sorted())
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        for (index, file) in candidate.files.enumerated() {
            let url = directory.appendingPathComponent(file.role.rawValue)
            XCTAssertEqual(try Data(contentsOf: url), fixture.decoded[index])
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            try candidate.withFileDescriptor(for: file.role) { fd in
                var s = stat(); XCTAssertEqual(fstat(fd, &s), 0)
                XCTAssertEqual(UInt64(s.st_ino), file.inode)
                XCTAssertEqual(fcntl(fd, F_GETFL) & O_ACCMODE, O_RDONLY)
            }
        }
        let moved = root.appendingPathComponent("renamed")
        try FileManager.default.moveItem(at: directory, to: moved)
        try candidate.withFileDescriptor(for: .binary) { fd in
            var byte: UInt8 = 0
            XCTAssertEqual(pread(fd, &byte, 1, 0), 1)
            XCTAssertEqual(byte, fixture.decoded[0].first)
        }
        XCTAssertThrowsError(try candidate.discard())
        try FileManager.default.moveItem(at: moved, to: directory)
        try candidate.discard()
        try candidate.discard()
        XCTAssertEqual(try children(root), [])
        XCTAssertThrowsError(try candidate.withFileDescriptor(for: .binary) { _ in })
    }
    func testCancellationBeforeDuringAndAfterPublish() throws {
        let root = try root(), payload = try StagingFixture().payload()
        let coordinator = try AppleCoreStagingCoordinator(stagingParent: root)
        XCTAssertThrowsError(try coordinator.stage(payload, cancelled: { true }))
        var polls = 0
        XCTAssertThrowsError(try coordinator.stage(payload, cancelled: { polls += 1; return polls >= 3 }))
        XCTAssertEqual(try children(root), [])
        var cancelled = false, io = AppleCoreStagingIO()
        io.checkpoint = { phase, _ in if phase == "afterPublish" { cancelled = true } }
        let after = try AppleCoreStagingCoordinator(stagingParent: root, io: io)
        let candidate = try after.stage(payload, cancelled: { cancelled })
        XCTAssertTrue(cancelled)
        try candidate.discard()
    }
    func testShortWritesInterruptedIOAndFailures() throws {
        let root = try root(), fixture = try StagingFixture(), payload = try fixture.payload()
        var io = AppleCoreStagingIO(), writes = 0, reads = 0
        io.write = { fd, bytes, count in
            writes += 1
            if writes == 1 { errno = EINTR; return -1 }
            return Darwin.write(fd, bytes, min(7, count))
        }
        io.read = { fd, bytes, count, offset in
            reads += 1
            if reads == 1 { errno = EINTR; return -1 }
            return pread(fd, bytes, min(11, count), offset)
        }
        let candidate = try AppleCoreStagingCoordinator(stagingParent: root, io: io).stage(payload)
        XCTAssertGreaterThan(writes, 3); XCTAssertGreaterThan(reads, 3)
        try candidate.discard()
        for failure in ["write", "read", "writeZero", "readZero", "close", "EXDEV"] {
            var broken = AppleCoreStagingIO()
            if failure == "write" { broken.write = { _, _, _ in errno = ENOSPC; return -1 } }
            if failure == "writeZero" { broken.write = { _, _, _ in 0 } }
            if failure == "readZero" { broken.read = { _, _, _, _ in 0 } }
            if failure == "read" { broken.read = { _, _, _, _ in errno = EIO; return -1 } }
            if failure == "close" { broken.closeWriter = { fd in _ = close(fd); errno = EIO; return -1 } }
            if failure == "EXDEV" { broken.rename = { _, _, _ in errno = EXDEV; return -1 } }
            XCTAssertThrowsError(try AppleCoreStagingCoordinator(stagingParent: root, io: broken).stage(payload), failure)
            XCTAssertEqual(try children(root), [], failure)
        }
    }
    func testExclusivePublishPreservesExistingTargetAndReturnsUncertainCandidate() throws {
        let root = try root(), payload = try StagingFixture().payload()
        var io = AppleCoreStagingIO()
        var existing: URL?
        io.rename = { parent, temporary, target in
            let destination = root.appendingPathComponent(target)
            existing = destination
            XCTAssertEqual(mkdirat(parent, target, 0o700), 0)
            try! Data("sentinel".utf8).write(to: destination.appendingPathComponent("sentinel"))
            return renameatx_np(parent, temporary, parent, target, UInt32(RENAME_EXCL))
        }
        XCTAssertThrowsError(try AppleCoreStagingCoordinator(stagingParent: root, io: io).stage(payload))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(existing).appendingPathComponent("sentinel")), Data("sentinel".utf8))
        XCTAssertEqual(try children(root).count, 1)
        var uncertain = AppleCoreStagingIO()
        uncertain.checkpoint = { phase, _ in if phase == "afterPublish" { throw CocoaError(.fileReadUnknown) } }
        do {
            _ = try AppleCoreStagingCoordinator(stagingParent: root, io: uncertain).stage(payload)
            XCTFail("Expected published uncertainty")
        } catch AppleCoreStagingError.publishedButUnconfirmed(let candidate, _) {
            XCTAssertTrue(try children(root).contains(candidate.name))
            try candidate.discard()
        }
    }
    func testCleanupMismatchAndUnknownChildRetainResidual() throws {
        for mismatch in [false, true] {
            let root = try root(), payload = try StagingFixture().payload()
            var io = AppleCoreStagingIO()
            io.checkpoint = { phase, directory in
                if phase == "beforePublish" {
                    if mismatch {
                        XCTAssertEqual(unlinkat(directory, "LICENSE", 0), 0)
                        let replacement = openat(directory, "LICENSE", O_CREAT | O_EXCL | O_WRONLY, 0o600)
                        XCTAssertGreaterThanOrEqual(replacement, 0); close(replacement)
                    } else {
                        let unknown = openat(directory, "unknown", O_CREAT | O_EXCL | O_WRONLY, 0o600)
                        XCTAssertGreaterThanOrEqual(unknown, 0); close(unknown)
                    }
                    throw CocoaError(.fileReadUnknown)
                }
            }
            do {
                _ = try AppleCoreStagingCoordinator(stagingParent: root, io: io).stage(payload)
                XCTFail("Expected residual")
            } catch AppleCoreStagingError.cleanupIncomplete(let operation, let residual, _) {
                XCTAssertEqual(residual, ".incomplete-" + operation)
                XCTAssertEqual(try children(root), [residual])
                XCTAssertTrue(try children(root.appendingPathComponent(residual)).contains(mismatch ? "LICENSE" : "unknown"))
            }
        }
    }
    private func installACL(_ fd: Int32, inherit: Bool = false) throws {
        var value = acl_init(1)
        defer { if let value { acl_free(UnsafeMutableRawPointer(value)) } }
        var entry: acl_entry_t?
        XCTAssertEqual(acl_create_entry(&value, &entry), 0)
        let actual = try XCTUnwrap(entry)
        XCTAssertEqual(acl_set_tag_type(actual, ACL_EXTENDED_ALLOW), 0)
        var identity = UUID().uuid
        XCTAssertEqual(acl_set_qualifier(actual, &identity), 0)
        var permissions: acl_permset_t?
        XCTAssertEqual(acl_get_permset(actual, &permissions), 0)
        XCTAssertEqual(acl_add_perm(try XCTUnwrap(permissions), ACL_READ_DATA), 0)
        if inherit {
            var flags: acl_flagset_t?
            XCTAssertEqual(acl_get_flagset_np(UnsafeMutableRawPointer(actual), &flags), 0)
            XCTAssertEqual(acl_add_flag_np(try XCTUnwrap(flags), ACL_ENTRY_FILE_INHERIT), 0)
            XCTAssertEqual(acl_add_flag_np(try XCTUnwrap(flags), ACL_ENTRY_DIRECTORY_INHERIT), 0)
        }
        XCTAssertEqual(acl_set_fd(fd, try XCTUnwrap(value)), 0)
    }
    func testRejectModesSymlinkAncestryAndACL() throws {
        let root = try root(), payload = try StagingFixture().payload()
        XCTAssertEqual(chmod(root.path, 0o755), 0)
        XCTAssertThrowsError(try AppleCoreStagingCoordinator(stagingParent: root))
        XCTAssertEqual(chmod(root.path, 0o700), 0)
        let link = URL(fileURLWithPath: root.path + "-symlink")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: link) }
        XCTAssertThrowsError(try AppleCoreStagingCoordinator(stagingParent: link))
        var io = AppleCoreStagingIO()
        io.checkpoint = { phase, fd in if phase == "createdFile" { try self.installACL(fd) } }
        XCTAssertThrowsError(try AppleCoreStagingCoordinator(stagingParent: root, io: io).stage(payload))
        XCTAssertEqual(try children(root), [])
        // A directory ACL installed after acquisition is actually inherited by the newly created leaf.
        var inherited = AppleCoreStagingIO(), observedInheritance = false
        inherited.checkpoint = { phase, fd in
            if phase == "createdDirectory" { try self.installACL(fd, inherit: true) }
            if phase == "createdFile" { observedInheritance = true }
        }
        XCTAssertThrowsError(try AppleCoreStagingCoordinator(stagingParent: root, io: inherited).stage(payload))
        XCTAssertFalse(observedInheritance, "Metadata validation must reject the inherited leaf ACL before the file hook")
        XCTAssertEqual(try children(root).count, 1, "Changed directory ACL prevents automatic cleanup")
        let parentFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        XCTAssertGreaterThanOrEqual(parentFD, 0)
        defer { close(parentFD) }
        try installACL(parentFD, inherit: true)
        XCTAssertThrowsError(try AppleCoreStagingCoordinator(stagingParent: root))
    }
    func testBoundedWritesCancellationAndFinalHashRevalidation() throws {
        let root = try root(), payload = try StagingFixture(binaryPadding: 131_073).payload()
        var writes = 0, io = AppleCoreStagingIO()
        io.write = { fd, bytes, count in
            XCTAssertLessThanOrEqual(count, 65_536)
            writes += 1
            return Darwin.write(fd, bytes, count)
        }
        XCTAssertThrowsError(try AppleCoreStagingCoordinator(stagingParent: root, io: io).stage(payload, cancelled: { writes > 0 }))
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(try children(root), [])
        var changed = AppleCoreStagingIO()
        changed.checkpoint = { phase, directory in
            if phase == "beforePublish" {
                let fd = openat(directory, "bimeron", O_WRONLY | O_NOFOLLOW)
                XCTAssertGreaterThanOrEqual(fd, 0)
                defer { close(fd) }
                var byte: UInt8 = 0
                XCTAssertEqual(pwrite(fd, &byte, 1, 0), 1)
            }
        }
        XCTAssertThrowsError(try AppleCoreStagingCoordinator(stagingParent: root, io: changed).stage(payload))
        XCTAssertEqual(try children(root), [])
    }
    func testPreexistingSymlinkIsNeverFollowedOrRemoved() throws {
        let root = try root(), payload = try StagingFixture().payload()
        let sentinel = root.appendingPathComponent("sentinel")
        let original = Data("preserve existing user bytes".utf8)
        try original.write(to: sentinel)
        let before = try FileManager.default.attributesOfItem(atPath: sentinel.path)
        var io = AppleCoreStagingIO()
        io.checkpoint = { phase, directory in
            if phase == "createdDirectory" { XCTAssertEqual(symlinkat(sentinel.path, directory, "bimeron"), 0) }
        }
        do {
            _ = try AppleCoreStagingCoordinator(stagingParent: root, io: io).stage(payload)
            XCTFail("Expected identity-aware residual")
        } catch AppleCoreStagingError.cleanupIncomplete(_, let residual, _) {
            let link = root.appendingPathComponent(residual).appendingPathComponent("bimeron")
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), sentinel.path)
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), original)
        let after = try FileManager.default.attributesOfItem(atPath: sentinel.path)
        XCTAssertEqual(before[.systemFileNumber] as? NSNumber, after[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
    }
    private func matchingDescriptors(_ identities: Set<String>) throws -> [Int32] {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").compactMap { name in
            guard let fd = Int32(name) else { return nil }
            var observed = stat()
            guard fstat(fd, &observed) == 0, identities.contains("\(observed.st_dev):\(observed.st_ino)") else { return nil }
            return fd
        }
    }
    private func assertClosed(_ descriptors: [Int32], file: StaticString = #filePath, line: UInt = #line) {
        for fd in descriptors {
            XCTAssertEqual(fcntl(fd, F_GETFD), -1, file: file, line: line)
            XCTAssertEqual(errno, EBADF, file: file, line: line)
        }
    }
    func testReentrantDiscardAndActualDescriptorRelease() throws {
        let root = try root(), payload = try StagingFixture().payload()
        let coordinator = try AppleCoreStagingCoordinator(stagingParent: root)
        let candidate = try coordinator.stage(payload)
        var directoryInfo = stat()
        XCTAssertEqual(stat(root.appendingPathComponent(candidate.name).path, &directoryInfo), 0)
        var identities = Set(candidate.files.map { "\($0.device):\($0.inode)" })
        identities.insert("\(directoryInfo.st_dev):\(directoryInfo.st_ino)")
        let retained = try matchingDescriptors(identities)
        XCTAssertEqual(retained.count, 4, "Candidate holds exactly three files and one directory")
        var borrowed: Int32 = -1
        try candidate.withFileDescriptor(for: .binary) { fd in
            borrowed = fd
            try candidate.discard() // The callback executes outside the candidate lock.
            assertClosed(retained)
            var first: UInt8 = 0
            XCTAssertEqual(pread(fd, &first, 1, 0), 1)
            XCTAssertEqual(first, payload.files[0].contents.first)
        }
        assertClosed([borrowed])
        XCTAssertEqual(try children(root), [])

        var failedHandles: [Int32] = [], io = AppleCoreStagingIO()
        io.checkpoint = { phase, directory in
            if phase == "beforePublish" {
                var ids = Set<String>()
                var observed = stat()
                XCTAssertEqual(fstat(directory, &observed), 0)
                ids.insert("\(observed.st_dev):\(observed.st_ino)")
                for role in AppleCorePayloadRole.allCases {
                    XCTAssertEqual(fstatat(directory, role.rawValue, &observed, AT_SYMLINK_NOFOLLOW), 0)
                    ids.insert("\(observed.st_dev):\(observed.st_ino)")
                }
                failedHandles = try self.matchingDescriptors(ids)
                XCTAssertEqual(failedHandles.count, 4)
                throw CocoaError(.fileReadUnknown)
            }
        }
        let failed = try AppleCoreStagingCoordinator(stagingParent: root, io: io)
        XCTAssertThrowsError(try failed.stage(payload))
        assertClosed(failedHandles)
        XCTAssertEqual(try children(root), [])
    }
    func testOneActiveOperation() throws {
        let root = try root(), payload = try StagingFixture().payload()
        var coordinator: AppleCoreStagingCoordinator!
        var tested = false, io = AppleCoreStagingIO()
        io.checkpoint = { phase, _ in
            if phase == "createdDirectory" {
                tested = true
                XCTAssertThrowsError(try coordinator.stage(payload)) { error in
                    guard case AppleCoreStagingError.busy = error else { return XCTFail("Expected busy") }
                }
            }
        }
        coordinator = try AppleCoreStagingCoordinator(stagingParent: root, io: io)
        let candidate = try coordinator.stage(payload)
        XCTAssertTrue(tested)
        try candidate.discard()
    }
}
