import CryptoKit
import Foundation

public enum AppleCoreReleaseError: Error { case invalidManifest, invalidSignature, unapproved, invalidArchive }

/// Local approval must come from an independent review, never from the downloaded manifest.
public struct AppleCoreReleaseApproval: Sendable {
    public let tag: String
    public let sourceRevision: String
    public init(tag: String, sourceRevision: String) {
        self.tag = tag
        self.sourceRevision = sourceRevision
    }
}

public struct AppleCoreReleaseManifest: Sendable {
    public let tag: String
    public let sourceRevision: String
    public let archiveName: String
    public let archiveSize: Int64
    public let archiveSHA256: String
    fileprivate init(_ manifest: Manifest, _ archive: Manifest.Archive) {
        tag = manifest.tag
        sourceRevision = manifest.source_revision
        archiveName = archive.name
        archiveSize = archive.size
        archiveSHA256 = archive.sha256
    }
}

/// Confirms complete archive bytes only; extraction safety and runtime readiness are separate gates.
public struct AppleCoreReleaseVerifiedArchive: Sendable {
    public let manifest: AppleCoreReleaseManifest
    public let data: Data
    fileprivate init(manifest: AppleCoreReleaseManifest, data: Data) {
        self.manifest = manifest
        self.data = data
    }
}

public enum AppleCoreRelease {
    public static let manifestLimit = 65_536
    public static let archiveLimit: Int64 = 268_435_456

    public static func verifyManifest(
        _ data: Data, signature: Data, trustedPublicKey: Data,
        approval: AppleCoreReleaseApproval, appVersion: String, channel: String, architecture: String
    ) throws -> AppleCoreReleaseManifest {
        guard !data.isEmpty, data.count <= manifestLimit else { throw AppleCoreReleaseError.invalidManifest }
        guard trustedPublicKey.count == 32, signature.count == 89, signature.last == 10,
              let encoded = String(data: signature.dropLast(), encoding: .ascii),
              let raw = Data(base64Encoded: encoded), raw.count == 64,
              raw.base64EncodedString() == encoded,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: trustedPublicKey),
              key.isValidSignature(raw, for: data) else { throw AppleCoreReleaseError.invalidSignature }
        // Authenticate original bounded bytes before any JSON interpretation.
        guard data.last == 10, data.dropLast().last == 125,
              String(data: data, encoding: .utf8) != nil else { throw AppleCoreReleaseError.invalidManifest }
        try rejectDuplicateKeys(data)
        let manifest: Manifest
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            try validateKeys(object)
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch { throw AppleCoreReleaseError.invalidManifest }
        let c = manifest.compatibility
        guard manifest.schema == 1, manifest.product == "bimeron-apple-core",
              validCoreVersion(manifest.core_version), manifest.tag == "v" + manifest.core_version,
              matches(manifest.source_revision, "^[0-9a-f]{40}$"),
              manifest.channel == channel, !channel.isEmpty,
              manifest.key_id == hex(SHA256.hash(data: trustedPublicKey).prefix(8)),
              c.schema == 1, c.ipc_min == 1, c.ipc_max == 1, c.profile_format == 1,
              c.daemon_session_guards,
              let minimum = triplet(c.app_min), let maximum = triplet(c.app_max_exclusive),
              let current = triplet(appVersion), minimum.lexicographicallyPrecedes(maximum),
              !current.lexicographicallyPrecedes(minimum), current.lexicographicallyPrecedes(maximum)
        else { throw AppleCoreReleaseError.invalidManifest }
        guard c.apple_reviewed, approval.tag == manifest.tag,
              approval.sourceRevision == manifest.source_revision else { throw AppleCoreReleaseError.unapproved }
        guard ["amd64", "arm64"].contains(architecture), manifest.archives.count == 2,
              Set(manifest.archives.map(\.arch)) == Set(["amd64", "arm64"]),
              manifest.archives.allSatisfy({ archive in
                  archive.os == "macos" && archive.name == "bimeron-\(manifest.tag)-macos-\(archive.arch).zip"
                      && archive.size > 0 && archive.size <= archiveLimit
                      && matches(archive.sha256, "^[0-9a-f]{64}$")
              }), let selected = manifest.archives.first(where: { $0.arch == architecture })
        else { throw AppleCoreReleaseError.invalidManifest }
        return AppleCoreReleaseManifest(manifest, selected)
    }

    public static func verifyArchive(_ data: Data, manifest: AppleCoreReleaseManifest) throws -> AppleCoreReleaseVerifiedArchive {
        guard data.count <= archiveLimit, Int64(data.count) == manifest.archiveSize,
              hex(SHA256.hash(data: data)) == manifest.archiveSHA256 else { throw AppleCoreReleaseError.invalidArchive }
        return AppleCoreReleaseVerifiedArchive(manifest: manifest, data: data)
    }

    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
    }
    private static func triplet(_ value: String) -> [UInt64]? {
        guard matches(value, "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$") else { return nil }
        let numbers = value.split(separator: ".").compactMap { UInt64($0) }
        return numbers.count == 3 ? numbers : nil
    }
    private static func validCoreVersion(_ value: String) -> Bool {
        let parts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard triplet(String(parts[0])) != nil else { return false }
        guard parts.count == 2 else { return true }
        return parts[1].split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            let identifier = String($0)
            return matches(identifier, "^[0-9A-Za-z-]+$")
                && (!matches(identifier, "^[0-9]+$") || identifier == "0" || !identifier.hasPrefix("0"))
        }
    }

    private static func validateKeys(_ value: Any) throws {
        func exact(_ value: Any, _ keys: String) throws -> [String: Any] {
            guard let object = value as? [String: Any], Set(object.keys) == Set(keys.split(separator: " ").map(String.init)) else {
                throw AppleCoreReleaseError.invalidManifest
            }
            return object
        }
        let root = try exact(value, "schema product tag core_version channel source_revision key_id compatibility archives")
        _ = try exact(root["compatibility"] as Any, "schema app_min app_max_exclusive apple_reviewed ipc_min ipc_max profile_format daemon_session_guards")
        guard let archives = root["archives"] as? [Any] else { throw AppleCoreReleaseError.invalidManifest }
        for archive in archives { _ = try exact(archive, "os arch name size sha256") }
    }

    // JSONDecoder accepts duplicates, including escaped spellings. Decode each key before comparing.
    private static func rejectDuplicateKeys(_ data: Data) throws {
        let bytes = Array(data)
        var objects: [Set<String>] = []
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 123: objects.append([])
            case 125:
                guard !objects.isEmpty else { throw AppleCoreReleaseError.invalidManifest }
                objects.removeLast()
            case 34:
                let start = index
                index += 1
                while index < bytes.count && bytes[index] != 34 {
                    if bytes[index] == 92 { index += 1 }
                    index += 1
                }
                guard index < bytes.count else { throw AppleCoreReleaseError.invalidManifest }
                var next = index + 1
                while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
                if next < bytes.count && bytes[next] == 58 {
                    guard !objects.isEmpty else { throw AppleCoreReleaseError.invalidManifest }
                    let key = try JSONDecoder().decode(String.self, from: Data(bytes[start...index]))
                    guard objects[objects.count - 1].insert(key.lowercased()).inserted else { throw AppleCoreReleaseError.invalidManifest }
                }
            default: break
            }
            index += 1
        }
    }
}

fileprivate struct Manifest: Decodable {
    let schema: Int
    let product, tag, core_version, channel, source_revision, key_id: String
    let compatibility: Compatibility
    let archives: [Archive]
    struct Compatibility: Decodable {
        let schema: Int
        let app_min, app_max_exclusive: String
        let apple_reviewed: Bool
        let ipc_min, ipc_max, profile_format: Int
        let daemon_session_guards: Bool
    }
    struct Archive: Decodable {
        let os, arch, name: String
        let size: Int64
        let sha256: String
    }
}
