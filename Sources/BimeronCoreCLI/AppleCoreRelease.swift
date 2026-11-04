import CryptoKit
import Foundation

public enum AppleCoreReleaseError: Error { case invalidManifest, invalidSignature, unapproved, invalidArchive }

/// Local approval must come from an independent review, never from the downloaded manifest.
public struct AppleCoreReleaseApproval: Sendable, Equatable {
    public let tag: String
    public let sourceRevision: String
    public init(tag: String, sourceRevision: String) {
        self.tag = tag
        self.sourceRevision = sourceRevision
    }
}

/// Caller-supplied provenance is bookkeeping, never an authenticated claim or a new trust pin.
public struct AppleCoreVerificationContext: Sendable, Equatable {
    public enum Classification: String, Sendable { case unspecified, syntheticUntrusted, independentlyConfigured }
    public let classification: Classification
    public let approvalIdentity, pinProvenance, appleBuildIdentity: String
    public init(classification: Classification, approvalIdentity: String, pinProvenance: String, appleBuildIdentity: String) {
        self.classification = classification
        self.approvalIdentity = approvalIdentity
        self.pinProvenance = pinProvenance
        self.appleBuildIdentity = appleBuildIdentity
    }
    public static let unspecified = Self(classification: .unspecified, approvalIdentity: "", pinProvenance: "", appleBuildIdentity: "")
}

/// Created indivisibly by the verifier; consumers must apply their own trust policy to these original bytes.
public struct AppleCoreVerificationEvidence: Sendable {
    public let signedManifest, signature, publicKey: Data
    public let keyID, appVersion, channel, architecture: String
    public let approval: AppleCoreReleaseApproval
    public let context: AppleCoreVerificationContext
    public let policyRevision = "apple-core-static-v1"
    fileprivate init(manifest: Data, signature: Data, publicKey: Data, keyID: String,
                     appVersion: String, channel: String, architecture: String,
                     approval: AppleCoreReleaseApproval, context: AppleCoreVerificationContext) {
        signedManifest = manifest; self.signature = signature; self.publicKey = publicKey
        self.keyID = keyID; self.appVersion = appVersion; self.channel = channel; self.architecture = architecture
        self.approval = approval; self.context = context
    }
}

public struct AppleCoreReleaseManifest: Sendable {
    public let evidence: AppleCoreVerificationEvidence
    public let tag: String
    public let sourceRevision: String
    public let coreVersion: String
    public let architecture: String
    public let archiveName: String
    public let archiveSize: Int64
    public let archiveSHA256: String
    fileprivate init(_ manifest: Manifest, _ archive: Manifest.Archive, evidence: AppleCoreVerificationEvidence) {
        self.evidence = evidence
        tag = manifest.tag
        sourceRevision = manifest.source_revision
        coreVersion = manifest.core_version
        architecture = archive.arch
        archiveName = archive.name
        archiveSize = archive.size
        archiveSHA256 = archive.sha256
    }
}

/// Fixed roles are the only output instructions crossing the archive gate.
public enum AppleCorePayloadRole: String, CaseIterable, Sendable {
    case binary = "bimeron", license = "LICENSE", notices = "THIRD_PARTY_NOTICES.txt"
}

public struct AppleCoreVerifiedFile: Sendable {
    public let role: AppleCorePayloadRole
    public let contents: Data
    public let sha256: String
    public var count: Int { contents.count }
    fileprivate init(role: AppleCorePayloadRole, contents: Data) {
        self.role = role; self.contents = contents; sha256 = AppleCoreRelease.digest(contents)
    }
}

/// Exact owned contents, returned only after the entire authenticated static gate succeeds.
/// Archive storage is released when verification returns; no path or ZIP plan crosses this boundary.
public struct AppleCoreReleaseVerifiedArchive: Sendable {
    public let manifest: AppleCoreReleaseManifest
    public let files: [AppleCoreVerifiedFile]
    fileprivate init(manifest: AppleCoreReleaseManifest, contents: [AppleCorePayloadRole: Data]) {
        self.manifest = manifest
        files = AppleCorePayloadRole.allCases.map { AppleCoreVerifiedFile(role: $0, contents: contents[$0]!) }
    }
}

public enum AppleCoreRelease {
    public static let manifestLimit = 65_536
    public static let archiveLimit: Int64 = 268_435_456

    public static func verifyManifest(
        _ data: Data, signature: Data, trustedPublicKey: Data,
        approval: AppleCoreReleaseApproval, appVersion: String, channel: String, architecture: String,
        context: AppleCoreVerificationContext = .unspecified
    ) throws -> AppleCoreReleaseManifest {
        try verifyManifestSnapshot(data, signature: signature, trustedPublicKey: trustedPublicKey, approval: approval,
            appVersion: appVersion, channel: channel, architecture: architecture, context: context, afterSnapshot: {})
    }

    // Per-call seam verifies alias mutation between snapshot acquisition and actual authentication.
    static func verifyManifestSnapshot(
        _ data: Data, signature: Data, trustedPublicKey: Data,
        approval: AppleCoreReleaseApproval, appVersion: String, channel: String, architecture: String,
        context: AppleCoreVerificationContext, afterSnapshot: () -> Void
    ) throws -> AppleCoreReleaseManifest {
        guard !data.isEmpty, data.count <= manifestLimit else { throw AppleCoreReleaseError.invalidManifest }
        guard trustedPublicKey.count == 32, signature.count == 89 else { throw AppleCoreReleaseError.invalidSignature }
        guard [appVersion, channel, architecture, approval.tag, approval.sourceRevision,
               context.approvalIdentity, context.pinProvenance, context.appleBuildIdentity].allSatisfy({ $0.utf8.count <= 1024 })
        else { throw AppleCoreReleaseError.invalidManifest }
        // Data(referencing:) and no-copy Data can alias external writable storage; detach before authentication.
        let data = owned(data), signature = owned(signature), trustedPublicKey = owned(trustedPublicKey)
        afterSnapshot()
        guard signature.last == 10,
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
              manifest.channel == channel,
              channel == (manifest.core_version.contains("-") ? "beta" : "stable"),
              manifest.key_id == hex(SHA256.hash(data: trustedPublicKey).prefix(8)),
              c.schema == 1, c.ipc_min == 1, c.ipc_max == 1, c.profile_format == 1,
              c.daemon_session_guards,
              let minimum = triplet(c.app_min), let maximum = triplet(c.app_max_exclusive),
              let current = triplet(appVersion), minimum.lexicographicallyPrecedes(maximum, by: decimalLess),
              !current.lexicographicallyPrecedes(minimum, by: decimalLess), current.lexicographicallyPrecedes(maximum, by: decimalLess)
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
        let evidence = AppleCoreVerificationEvidence(manifest: data, signature: signature, publicKey: trustedPublicKey,
            keyID: manifest.key_id, appVersion: appVersion, channel: channel, architecture: architecture,
            approval: approval, context: context)
        return AppleCoreReleaseManifest(manifest, selected, evidence: evidence)
    }

    public static func verifyArchive(_ data: Data, manifest: AppleCoreReleaseManifest) throws -> AppleCoreReleaseVerifiedArchive {
        try verifyArchiveSnapshot(data, manifest: manifest, afterSnapshot: {})
    }

    static func verifyArchiveSnapshot(_ data: Data, manifest: AppleCoreReleaseManifest, afterSnapshot: () -> Void) throws -> AppleCoreReleaseVerifiedArchive {
        guard data.count <= archiveLimit, Int64(data.count) == manifest.archiveSize else { throw AppleCoreReleaseError.invalidArchive }
        let snapshot = owned(data)
        afterSnapshot()
        guard digest(snapshot) == manifest.archiveSHA256 else { throw AppleCoreReleaseError.invalidArchive }
        let contents = try AppleArchiveGate.check(snapshot, architecture: manifest.architecture, revision: manifest.sourceRevision, version: manifest.coreVersion)
        return AppleCoreReleaseVerifiedArchive(manifest: manifest, contents: contents)
    }

    static func owned(_ bytes: Data) -> Data {
        bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return Data() }
            return Data(bytes: base, count: buffer.count)
        }
    }
    static func digest(_ bytes: Data) -> String { hex(SHA256.hash(data: bytes)) }

    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
    }
    private static func decimalLess(_ lhs: String, _ rhs: String) -> Bool {
        lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count
    }
    private static func triplet(_ value: String) -> [String]? {
        guard value.utf8.count <= 128, matches(value, "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$") else { return nil }
        let parts = value.split(separator: ".").map(String.init)
        let maximum = "18446744073709551615"
        guard parts.allSatisfy({ $0.count < maximum.count || ($0.count == maximum.count && $0 <= maximum) }) else { return nil }
        return parts
    }
    static func validCoreVersion(_ value: String) -> Bool {
        guard value.utf8.count <= 128 else { return false }
        let parts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard matches(String(parts[0]), "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$") else { return false }
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
            case 45, 48...57:
                let start = index
                while index < bytes.count && ([45, 43, 46, 69, 101].contains(bytes[index])
                        || (48...57).contains(bytes[index])) {
                    index += 1
                }
                let token = String(decoding: bytes[start..<index], as: UTF8.self)
                guard matches(token, "^(0|[1-9][0-9]*)$") else {
                    throw AppleCoreReleaseError.invalidManifest
                }
                index -= 1
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
