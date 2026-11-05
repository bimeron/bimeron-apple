import BimeronModel
import BimeronSSHAuth
import Foundation

/// Validates only explicitly supplied paths, leaving optional fields and imports portable.
enum SSHFileSelection {
    static func validatedURL(for input: String, role: SSHFileRole) throws -> URL? {
        let path = ProfileInput.normalized(input)
        guard !path.isEmpty else { return nil }
        guard !path.utf8.contains(0) else { throw SSHFilePreflightError.absolutePathRequired(role) }
        let resolved: String
        if let url = URL(string: path), url.isFileURL {
            guard url.host == nil || url.host == "" || url.host == "localhost" else {
                throw SSHFilePreflightError.absolutePathRequired(role)
            }
            // Check URL bytes before Foundation's filesystem-path conversion can preserve or normalize an encoded NUL.
            guard let decodedPath = url.path(percentEncoded: true).removingPercentEncoding,
                  !decodedPath.utf8.contains(0) else {
                throw SSHFilePreflightError.absolutePathRequired(role)
            }
            resolved = url.path
        } else {
            resolved = (path as NSString).expandingTildeInPath
        }
        try SSHFilePreflight.validateFile(resolved, role: role)
        return URL(fileURLWithPath: resolved)
    }

    static func errorKey(_ error: SSHFilePreflightError) -> String {
        switch error {
        case .absolutePathRequired: "SSH file must use an absolute path."
        case .missingOrNotRegular: "SSH file is missing or is not a regular file."
        case .notReadable: "SSH file is not readable by this app."
        }
    }
}
