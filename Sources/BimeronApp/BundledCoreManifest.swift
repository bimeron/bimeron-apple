import Foundation

struct BundledCoreManifest: Decodable {
    let sha256: String
    let detach_sha256: String
    let revision: String
    let production_shipping: Bool
    let provenance: String
    let version: String

    var displayIdentity: String { "Core \(version) (\(revision.prefix(8)))" }

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let resources = bundle.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(Self.self,
            from: Data(contentsOf: resources.appending(path: "CoreInstall/manifest.json")))
    }

    func permitsLaunch(revision expected: String) -> Bool {
        revision == expected && !production_shipping && provenance == "local-development-untrusted"
            && [sha256, detach_sha256].allSatisfy { $0.count == 64 && $0.allSatisfy { "0123456789abcdef".contains($0) } }
    }
}
