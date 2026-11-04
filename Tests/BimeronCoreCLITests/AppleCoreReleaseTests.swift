import CryptoKit
import Foundation
import XCTest
@testable import BimeronCoreCLI

final class AppleCoreReleaseTests: XCTestCase {
    // Fixed synthetic zero seed; never a release key.
    private let key = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0, count: 32))
    private let archive = Data("synthetic archive".utf8)
    private let revision = String(repeating: "a", count: 40)

    private func fixture() -> [String: Any] {
        let hash = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        return ["schema": 1, "product": "bimeron-apple-core", "tag": "v1.2.3-rc.1", "core_version": "1.2.3-rc.1",
                "channel": "beta", "source_revision": revision, "key_id": "139e3940e64b5491",
                "compatibility": ["schema": 1, "app_min": "0.1.0", "app_max_exclusive": "0.1.1", "apple_reviewed": true,
                                  "ipc_min": 1, "ipc_max": 1, "profile_format": 1, "daemon_session_guards": true],
                "archives": ["amd64", "arm64"].map { ["os": "macos", "arch": $0, "name": "bimeron-v1.2.3-rc.1-macos-\($0).zip", "size": archive.count, "sha256": hash] as [String: Any] }]
    }
    private func bytes(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(10)
        return data
    }
    private func verify(_ data: Data, publicKey: Data? = nil, approval: AppleCoreReleaseApproval? = nil,
                        app: String = "0.1.0", signature: Data? = nil) throws -> AppleCoreReleaseManifest {
        let sig = try signature ?? Data((key.signature(for: data).base64EncodedString() + "\n").utf8)
        return try AppleCoreRelease.verifyManifest(data, signature: sig, trustedPublicKey: publicKey ?? key.publicKey.rawRepresentation,
            approval: approval ?? AppleCoreReleaseApproval(tag: "v1.2.3-rc.1", sourceRevision: revision),
            appVersion: app, channel: "beta", architecture: "arm64")
    }
    func testPublisherSyntheticVector() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/workstreams/core-delivery/testdata")
        let data = try Data(contentsOf: root.appendingPathComponent("synthetic-reviewed-manifest.json"))
        let signature = try Data(contentsOf: root.appendingPathComponent("synthetic-reviewed-manifest.json.sig"))
        let vector = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("synthetic-vector.json"))) as! [String: String]
        for architecture in ["amd64", "arm64"] {
            let manifest = try AppleCoreRelease.verifyManifest(data, signature: signature,
                trustedPublicKey: XCTUnwrap(Data(base64Encoded: XCTUnwrap(vector["public_key_base64"]))),
                approval: .init(tag: XCTUnwrap(vector["expected_tag"]), sourceRevision: XCTUnwrap(vector["expected_source_revision"])),
                appVersion: "0.1.0", channel: "beta", architecture: architecture)
            XCTAssertEqual(manifest.archiveName, "bimeron-v0.1.0-beta.1-macos-\(architecture).zip")
            // Publisher vector authenticates a descriptor only; archive hashes are deliberately fake.
            XCTAssertThrowsError(try AppleCoreRelease.verifyArchive(Data([0]), manifest: manifest))
        }
    }
    func testReviewedApprovedArchive() throws {
        let manifest = try verify(bytes(fixture()))
        XCTAssertEqual(manifest.archiveName, "bimeron-v1.2.3-rc.1-macos-arm64.zip")
        // Hash-authenticated arbitrary bytes still fail the new packaging gate.
        XCTAssertThrowsError(try AppleCoreRelease.verifyArchive(archive, manifest: manifest))
        XCTAssertThrowsError(try AppleCoreRelease.verifyArchive(Data("wrong".utf8), manifest: manifest))
        XCTAssertThrowsError(try AppleCoreRelease.verifyArchive(Data(repeating: 0, count: archive.count), manifest: manifest))
    }
    func testTrustAndApproval() throws {
        let data = try bytes(fixture())
        XCTAssertThrowsError(try verify(data, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation))
        XCTAssertThrowsError(try verify(data, signature: Data(repeating: 65, count: 89)))
        XCTAssertThrowsError(try verify(data, approval: .init(tag: "v1.2.4", sourceRevision: revision)))
        XCTAssertThrowsError(try verify(data, approval: .init(tag: "v1.2.3-rc.1", sourceRevision: String(repeating: "b", count: 40))))
        for app in ["0.0.9", "0.1.1", "0.1.0-rc.1", "00.1.0"] { XCTAssertThrowsError(try verify(data, app: app)) }
    }
    func testRejectedFields() throws {
        for (field, value) in [("key_id", "139e3940"), ("key_id", "0000000000000000"), ("source_revision", String(repeating: "a", count: 40) + "\n"), ("tag", "v9.0.0"), ("source_revision", "abc"),
                               ("core_version", "01.2.3"), ("core_version", "1.2.3-01"), ("product", "other"),
                               ("channel", "other"), ("unknown", "extra")] {
            var object = fixture(); object[field] = value
            XCTAssertThrowsError(try verify(bytes(object)), field)
        }
        for (field, value) in [("apple_reviewed", false as Any), ("daemon_session_guards", false), ("schema", 2),
                               ("ipc_min", 0), ("ipc_max", 2), ("profile_format", 2), ("app_min", "0.1.1"),
                               ("app_max_exclusive", "0.1.0"), ("unknown", 1)] {
            var object = fixture(); var c = object["compatibility"] as! [String: Any]; c[field] = value; object["compatibility"] = c
            XCTAssertThrowsError(try verify(bytes(object)), field)
        }
        var missing = fixture(); missing.removeValue(forKey: "schema")
        XCTAssertThrowsError(try verify(bytes(missing)))
    }
    func testDecimalVersionBounds() throws {
        var object = fixture()
        var compatibility = object["compatibility"] as! [String: Any]
        compatibility["app_min"] = "2.0.0"
        compatibility["app_max_exclusive"] = "10.0.0"
        object["compatibility"] = compatibility
        XCTAssertNoThrow(try verify(bytes(object), app: "9.0.0"))
        XCTAssertThrowsError(try verify(bytes(object), app: "10.0.0"))
        compatibility["app_min"] = "18446744073709551614.0.0"
        compatibility["app_max_exclusive"] = "18446744073709551615.0.0"
        object["compatibility"] = compatibility
        XCTAssertNoThrow(try verify(bytes(object), app: "18446744073709551614.0.0"))
        compatibility["app_max_exclusive"] = "18446744073709551616.0.0"
        object["compatibility"] = compatibility
        XCTAssertThrowsError(try verify(bytes(object), app: "18446744073709551614.0.0"))
        object = fixture()
        object["core_version"] = "18446744073709551616.0.0-rc.1"
        object["tag"] = "v18446744073709551616.0.0-rc.1"
        var archives = object["archives"] as! [[String: Any]]
        for i in archives.indices { archives[i]["name"] = "bimeron-v18446744073709551616.0.0-rc.1-macos-\(archives[i]["arch"]!).zip" }
        object["archives"] = archives
        XCTAssertNoThrow(try verify(bytes(object), approval: .init(tag: "v18446744073709551616.0.0-rc.1", sourceRevision: revision)))
    }
    func testArchiveContract() throws {
        for (field, value) in [("size", 0 as Any), ("size", 268_435_457), ("sha256", "ABC"), ("arch", "x86_64"),
                               ("os", "linux"), ("name", "../bad.zip"), ("unknown", 1)] {
            var object = fixture(); var archives = object["archives"] as! [[String: Any]]; archives[0][field] = value; object["archives"] = archives
            XCTAssertThrowsError(try verify(bytes(object)), field)
        }
        var object = fixture(); let archives = object["archives"] as! [[String: Any]]
        object["archives"] = [archives[0], archives[0]]
        XCTAssertThrowsError(try verify(bytes(object)))
        object["archives"] = [archives[0]]
        XCTAssertThrowsError(try verify(bytes(object)))
    }
    func testIntegerTokensAreExact() throws {
        let text = String(decoding: try bytes(fixture()), as: UTF8.self)
        for token in ["1.00000000000000001", "1.0", "1e0", "-1", "01"] {
            let changed = text.replacingOccurrences(of: "\"schema\":1", with: "\"schema\":\(token)")
            XCTAssertThrowsError(try verify(Data(changed.utf8)), token)
        }
        let changed = text.replacingOccurrences(of: "\"size\":\(archive.count)", with: "\"size\":268435456.000000001")
        XCTAssertThrowsError(try verify(Data(changed.utf8)))
    }
    func testFramingDuplicatesAndBounds() throws {
        let data = try bytes(fixture())
        let text = String(decoding: data, as: UTF8.self)
        for prefix in ["\"schema\":1,", "\"sch\\u0065ma\":1,", "\"SCHEMA\":1,"] {
            XCTAssertThrowsError(try verify(Data(("{" + prefix + text.dropFirst()).utf8)))
        }
        for malformed in [Data(data.dropLast()), data + Data([10]), data + Data("{}\n".utf8),
                          Data(data.dropLast(2)) + Data(" \n".utf8), Data([0xff, 125, 10]),
                          Data(repeating: 32, count: 65_537)] {
            XCTAssertThrowsError(try verify(malformed))
        }
        let nestedDuplicate = text.replacingOccurrences(of: "\"ipc_min\":1", with: "\"ipc_min\":1,\"ipc_\\u006din\":1")
        XCTAssertThrowsError(try verify(Data(nestedDuplicate.utf8)))
        let originalSignature = Data((try key.signature(for: data).base64EncodedString() + "\n").utf8)
        XCTAssertThrowsError(try verify(Data([32]) + data, signature: originalSignature))
        let padded = Data(repeating: 32, count: 65_536 - data.count) + data
        XCTAssertNoThrow(try verify(padded))
        XCTAssertThrowsError(try verify(Data([32]) + padded))
        var object = fixture(); var archives = object["archives"] as! [[String: Any]]
        archives[0]["size"] = 268_435_456; object["archives"] = archives
        XCTAssertNoThrow(try verify(bytes(object)))
    }
}
