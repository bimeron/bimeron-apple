import BimeronCoreCLI
import Foundation

/// Development compatibility only. Neither metadata response establishes trust or service readiness.
enum SessionCoreSelection {
    case defaultResolver
    case probing
    case compatible(CoreCLI)
    case blocked

    var statusKey: String {
        switch self {
        case .defaultResolver: "Core: default resolver"
        case .probing: "Core: checking selected file"
        case .compatible: "Core: UNTRUSTED development compatibility"
        case .blocked: "Core: selection failed; reselect or reset"
        }
    }

    static func probe(_ cli: CoreCLI) async throws {
        guard cli.executableURL.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let values = try cli.executableURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true,
              FileManager.default.isExecutableFile(atPath: cli.executableURL.path) else {
            throw CocoaError(.fileReadNoPermission)
        }
        let version = try await cli.version()
        try Task.checkCancellation()
        guard version.platform == "darwin",
              !version.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let capabilities = try await cli.capabilities()
        try Task.checkCancellation()
        guard capabilities.platform == "darwin" else { throw CocoaError(.fileReadCorruptFile) }
    }
}
