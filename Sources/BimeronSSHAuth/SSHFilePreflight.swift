import Foundation

public enum SSHFileRole: Sendable { case knownHosts, identity }

public enum SSHFilePreflightError: Error, Equatable, Sendable {
    case absolutePathRequired(SSHFileRole)
    case missingOrNotRegular(SSHFileRole)
    case notReadable(SSHFileRole)
}

public enum SSHFilePreflight {
    /// Checks access by this process only; does not parse keys or establish host trust.
    public static func validate(knownHosts: String, identity: String? = nil) throws {
        try validateFile(knownHosts, role: .knownHosts)
        if let identity { try validateFile(identity, role: .identity) }
    }

    private static func validateFile(_ path: String, role: SSHFileRole) throws {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else {
            throw SSHFilePreflightError.absolutePathRequired(role)
        }
        let manager = FileManager.default
        guard let attributes = try? manager.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular else {
            throw SSHFilePreflightError.missingOrNotRegular(role)
        }
        guard manager.isReadableFile(atPath: path) else { throw SSHFilePreflightError.notReadable(role) }
    }
}
