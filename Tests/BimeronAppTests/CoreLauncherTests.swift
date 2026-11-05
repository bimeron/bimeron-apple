import Foundation
import Testing
@testable import BimeronApp

private func shell(_ script: String, _ arguments: [String]) throws -> (Int32, Data) {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", script, "test"] + arguments
    process.standardOutput = output
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, bytes)
}

@Test func rootAdminAncestorIsAcceptedWithoutRelaxingWriteChecks() throws {
    for group in ["0", "80"] {
        #expect(try shell(CoreLauncher.ancestorPredicate, ["0", group, "755"]).0 == 0)
        #expect(try shell(CoreLauncher.ancestorPredicate, ["0", group, "775"]).0 != 0)
        #expect(try shell(CoreLauncher.ancestorPredicate, ["0", group, "757"]).0 != 0)
        #expect(try shell(CoreLauncher.ancestorPredicate, ["501", group, "755"]).0 != 0)
    }
    #expect(CoreLauncher.script.contains("/usr/sbin/chown root:wheel"))
    #expect(CoreLauncher.script.contains("= 0:0:755"))
}

@Test func hostileBundlePathsRemainLiteralShellArguments() throws {
    let manifest = BundledCoreManifest(sha256: String(repeating: "a", count: 64),
        detach_sha256: String(repeating: "b", count: 64), revision: CoreConnection.revision,
        production_shipping: false, provenance: "local-development-untrusted")
    let path = "/Users/test/' '\u{301} \"\u{301} $HOME `id` \n\r Bimeron.app/Contents/MacOS"
    let args = CoreLauncher.arguments(binaries: URL(fileURLWithPath: path), manifest: manifest, uid: 501)
    #expect(args[1] == CoreLauncher.appleScript)
    #expect(args[3] == CoreLauncher.script)
    #expect(!args[1].contains(path))
    #expect(!args[3].contains(path))
    #expect(args[1].contains("quoted form of item n of argv"))
    // Run the actual source-copy lines with a harmless capture function, as a normal user.
    let copies = CoreLauncher.script.split(separator: "\n").filter { $0.contains("/usr/bin/install -o") }
        .joined(separator: "\n").replacingOccurrences(of: "/usr/bin/install -o root -g wheel -m 0755", with: "capture", options: .literal)
    let harness = "capture() { printf '%s\\000' \"$1\"; }; stage=unused\n" + copies
    let (status, data) = try shell(harness, Array(args[4...8]))
    #expect(status == 0)
    #expect(data == Data((args[4] + "\0" + args[5] + "\0").utf8))
}

@Test func writableBundleIsRejectedBeforeApproval() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                           attributes: [.posixPermissions: 0o777])
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: directory.path)
    #expect(throws: CoreLauncher.Failure.failed) { try CoreLauncher.validateBundleAncestry(directory) }
}
