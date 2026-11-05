import Foundation

struct BundledCoreManifest: Decodable {
    let package_sha256: String
    let revision: String
    let owner_uid: UInt32
    let production_shipping: Bool
    let provenance: String

    func permitsOpening(revision expectedRevision: String, ownerUID: UInt32, packageSHA256: String) -> Bool {
        revision == expectedRevision && owner_uid == ownerUID && !production_shipping
            && provenance == "local-development-untrusted" && package_sha256 == packageSHA256
    }
}
