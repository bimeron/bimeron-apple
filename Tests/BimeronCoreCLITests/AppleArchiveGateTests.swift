import CryptoKit
import Foundation
import XCTest
@testable import BimeronCoreCLI

final class AppleArchiveGateTests: XCTestCase {
    func testCanonicalRecords() throws {
        for version in ["0.1.0-beta.1", "18446744073709551616.0.0", String(repeating: "9", count: 124) + ".0.0"] {
            let record = Data(("BIMERON.APPLE.CORE.VERSION/v1\0" + String(format: "%03d", version.utf8.count) + ":" + version + "\0END.APPLE.CORE.RECORD/v1\0").utf8)
            XCTAssertEqual(try AppleArchiveGate.record(Data([1]) + record + Data([2])), version)
            XCTAssertThrowsError(try AppleArchiveGate.record(record + record))
            XCTAssertThrowsError(try AppleArchiveGate.record(record.dropLast()))
        }
        for version in ["", "01.2.3", "1.2.3-01", "1.2.3+build", "1.2.3-", "1.2.3\n", String(repeating: "9", count: 125) + ".0.0"] {
            XCTAssertFalse(AppleCoreRelease.validCoreVersion(version), version)
        }
    }

    func testMalformedBoundsFailClosed() throws {
        let prefix = Data("BIMERON.APPLE.CORE.VERSION/v1\0".utf8)
        for tail in ["", "001", "x01:1", "000:", "129:" + String(repeating: "1", count: 129), "005:1.2.3", "005;1.2.3\0END.APPLE.CORE.RECORD/v1\0", "005:1.2.3\0BAD.APPLE.CORE.RECORD/v1\0"] {
            XCTAssertThrowsError(try AppleArchiveGate.record(prefix + Data(tail.utf8)))
        }
        XCTAssertThrowsError(try AppleArchiveGate.record(Data(repeating: 0, count: 64 * 1024 * 1024 + 1)))
        for size in 0..<80 {
            let data = Data(repeating: 255, count: size)
            XCTAssertThrowsError(try AppleArchiveGate.binary(data, architecture: "arm64", revision: String(repeating: "0", count: 40), version: "1.2.3"))
            XCTAssertThrowsError(try AppleArchiveGate.check(data, architecture: "arm64", revision: String(repeating: "0", count: 40), version: "1.2.3"))
        }
    }

    func testLocalProducerInterop() throws {
        guard let path = ProcessInfo.processInfo.environment["BIMERON_APPLE_VECTORS"] else {
            throw XCTSkip("Set BIMERON_APPLE_VECTORS to locally generated real-Core parity vectors")
        }
        let root = URL(fileURLWithPath: path)
        let index = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: root.appendingPathComponent("index.json")))
        // Deterministic zero seed is synthetic test material, never a production trust pin.
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0, count: 32))
        for vector in index {
            let archive = try Data(contentsOf: root.appendingPathComponent(vector.file))
            let hash = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
            let revision = "e8de4354e2dc5d0364a2fb93119c50971cdf8a5c"
            let object: [String: Any] = ["schema": 1, "product": "bimeron-apple-core", "tag": "v0.1.0-beta.1", "core_version": "0.1.0-beta.1", "channel": "beta", "source_revision": revision, "key_id": "139e3940e64b5491",
                "compatibility": ["schema": 1, "app_min": "0.1.0", "app_max_exclusive": "0.1.1", "apple_reviewed": true, "ipc_min": 1, "ipc_max": 1, "profile_format": 1, "daemon_session_guards": true],
                "archives": try ["amd64", "arm64"].map { arch -> [String: Any] in
                    let bytes = arch == vector.arch ? archive : try Data(contentsOf: root.appendingPathComponent(arch + "-original.zip"))
                    let digest = arch == vector.arch ? hash : SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                    return ["os": "macos", "arch": arch, "name": "bimeron-v0.1.0-beta.1-macos-\(arch).zip", "size": bytes.count, "sha256": digest]
                }]
            let manifest = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data([10])
            let signature = Data((try key.signature(for: manifest).base64EncodedString() + "\n").utf8)
            let descriptor = try AppleCoreRelease.verifyManifest(manifest, signature: signature, trustedPublicKey: key.publicKey.rawRepresentation, approval: .init(tag: "v0.1.0-beta.1", sourceRevision: revision), appVersion: "0.1.0", channel: "beta", architecture: vector.arch)
            let accepted = (try? AppleCoreRelease.verifyArchive(archive, manifest: descriptor)) != nil
            XCTAssertEqual(accepted, vector.accept, vector.file)
            // Save exact deterministic signed full-archive evidence for parent inspection.
            try manifest.write(to: root.appendingPathComponent(vector.file + ".manifest.json"))
            try signature.write(to: root.appendingPathComponent(vector.file + ".manifest.sig"))
            XCTAssertThrowsError(try AppleCoreRelease.verifyArchive(archive + Data([0]), manifest: descriptor), vector.file)
        }
    }
    private struct Vector: Decodable { let file, arch: String; let accept: Bool }
}
