import BimeronSSHAuth
import Foundation
import Testing
@testable import BimeronApp

@Suite @MainActor struct SSHFileSelectionTests {
    @Test func optionalFieldsAndExplicitReadableFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "fake private key")
        let contents = Data("deliberately not an SSH key or known_hosts entry".utf8)
        try contents.write(to: file)
        for role in [SSHFileRole.knownHosts, .identity] {
            #expect(try SSHFileSelection.validatedURL(for: " \n", role: role) == nil)
            #expect(try SSHFileSelection.validatedURL(for: file.path, role: role) == file)
            #expect(try SSHFileSelection.validatedURL(for: file.absoluteString, role: role) == file)
        }
        #expect(try Data(contentsOf: file) == contents)
        try FileManager.default.removeItem(at: file)
        #expect(throws: SSHFilePreflightError.missingOrNotRegular(.identity)) {
            try SSHFileSelection.validatedURL(for: file.path, role: .identity)
        }
    }

    @Test func invalidPathsRetainTheirRoleAndUseSanitizedMessages() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for role in [SSHFileRole.knownHosts, .identity] {
            for path in ["relative-secret", "./relative-secret", "/tmp/secret\u{0}suffix", "file:///tmp/secret%00suffix", "file://remote/private-secret"] {
                #expect(throws: SSHFilePreflightError.absolutePathRequired(role)) {
                    try SSHFileSelection.validatedURL(for: path, role: role)
                }
            }
            for path in [directory.path, directory.appending(path: "missing-secret").path] {
                #expect(throws: SSHFilePreflightError.missingOrNotRegular(role)) {
                    try SSHFileSelection.validatedURL(for: path, role: role)
                }
            }
            #expect(SSHFileSelection.errorKey(.absolutePathRequired(role)) == "SSH file must use an absolute path.")
            #expect(SSHFileSelection.errorKey(.missingOrNotRegular(role)) == "SSH file is missing or is not a regular file.")
            #expect(SSHFileSelection.errorKey(.notReadable(role)) == "SSH file is not readable by this app.")
        }
    }

    @Test func unreadableFileUsesCurrentProcessAccess() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("fake".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        if FileManager.default.isReadableFile(atPath: file.path) {
            #expect(try SSHFileSelection.validatedURL(for: file.path, role: .identity) == file)
        } else {
            #expect(throws: SSHFilePreflightError.notReadable(.identity)) {
                try SSHFileSelection.validatedURL(for: file.path, role: .identity)
            }
        }
    }
}
