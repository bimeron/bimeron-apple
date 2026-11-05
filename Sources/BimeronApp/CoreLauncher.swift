import Foundation
import CryptoKit

struct CoreLauncher: Sendable {
    enum Failure: Error { case cancelled, failed, timeout, incompatible }

    static func launch() async throws {
        guard let resources = Bundle.main.resourceURL else { throw Failure.failed }
        let manifest = try JSONDecoder().decode(BundledCoreManifest.self,
            from: Data(contentsOf: resources.appending(path: "CoreInstall/manifest.json")))
        guard manifest.permitsLaunch(revision: CoreConnection.revision) else { throw Failure.failed }
        let binaries = resources.deletingLastPathComponent().appending(path: "MacOS")
        try verifyPayloads(binaries: binaries, manifest: manifest)
        try validateBundleAncestry(Bundle.main.bundleURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.arguments = arguments(binaries: binaries, manifest: manifest, uid: getuid())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let errorURL = directory.appending(path: "stderr")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errors = try FileHandle(forUpdating: errorURL)
        defer { try? errors.close() }
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        try errors.seek(toOffset: 0)
        let data = try errors.read(upToCount: 65536) ?? Data()
        guard status == 0 else {
            throw String(decoding: data, as: UTF8.self).contains("(-128)") ? Failure.cancelled : Failure.failed
        }
    }

    static func validateBundleAncestry(_ bundle: URL) throws {
        var current = bundle.standardizedFileURL
        while true {
            let values = try FileManager.default.attributesOfItem(atPath: current.path)
            guard values[.type] as? FileAttributeType == .typeDirectory,
                  let owner = values[.ownerAccountID] as? NSNumber,
                  let mode = values[.posixPermissions] as? NSNumber,
                  (owner.uint32Value == 0 || owner.uint32Value == getuid()),
                  mode.intValue & 0o022 == 0 else { throw Failure.failed }
            if current.path == "/" { break }
            current.deleteLastPathComponent()
        }
    }

    static let appleScript = """
    on run argv
      set shellCommand to "/bin/sh -c " & quoted form of item 1 of argv & " bimeron"
      repeat with n from 2 to 6
        set shellCommand to shellCommand & " " & quoted form of item n of argv
      end repeat
      do shell script shellCommand with administrator privileges with prompt (item 7 of argv)
    end run
    """

    static func arguments(binaries: URL, manifest: BundledCoreManifest, uid: UInt32) -> [String] {
        ["-e", appleScript, "--", script,
         binaries.appending(path: "bimeron-core").path,
         binaries.appending(path: "bimeron-detach").path,
         manifest.sha256, manifest.detach_sha256, String(uid),
         String(localized: "Bimeron needs administrator approval to install and start its development Core.", bundle: .module)]
    }

    static func verifyPayloads(binaries: URL, manifest: BundledCoreManifest) throws {
        for (name, expected) in [("bimeron-core", manifest.sha256), ("bimeron-detach", manifest.detach_sha256)] {
            let digest = SHA256.hash(data: try Data(contentsOf: binaries.appending(path: name)))
                .map { String(format: "%02x", $0) }.joined()
            guard digest == expected else { throw Failure.failed }
        }
    }

    static let ancestorPredicate = """
    [ "$1" = 0 ] && [ $((0$3 & 0022)) -eq 0 ]
    """

    static let script = """
        set -eu
        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        export PATH
        cd /
        protected() {
          [ ! -L "$1" ] && [ -d "$1" ]
          /bin/sh -c '\(ancestorPredicate)' check "$(/usr/bin/stat -f %u "$1")" "$(/usr/bin/stat -f %g "$1")" "$(/usr/bin/stat -f %Lp "$1")"
          [ "$(/bin/ls -lde "$1" | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = 1 ]
        }
        for dir in / /Library '/Library/Application Support'; do protected "$dir"; done
        for dir in '/Library/Application Support/Bimeron' '/Library/Application Support/Bimeron/DevCore'; do
          if [ ! -e "$dir" ] && [ ! -L "$dir" ]; then
            /bin/mkdir -m 0755 "$dir"
            /usr/sbin/chown root:wheel "$dir"
          fi
          protected "$dir"
          [ "$(/usr/bin/stat -f %u:%g:%Lp "$dir")" = 0:0:755 ]
        done
        destination='/Library/Application Support/Bimeron/DevCore'
        for name in bimeron-core bimeron-detach; do
          [ ! -L "$destination/$name" ]
          if [ -e "$destination/$name" ]; then
            [ -f "$destination/$name" ]
            [ "$(/usr/bin/stat -f %u:%g:%Lp "$destination/$name")" = 0:0:755 ]
          fi
        done
        stage=$(/usr/bin/mktemp -d "$destination/stage.XXXXXXXX")
        trap '/bin/rm -rf "$stage"' EXIT
        /usr/bin/install -o root -g wheel -m 0755 "$1" "$stage/bimeron-core"
        /usr/bin/install -o root -g wheel -m 0755 "$2" "$stage/bimeron-detach"
        [ "$(/usr/bin/shasum -a 256 "$stage/bimeron-core" | /usr/bin/cut -d ' ' -f 1)" = "$3" ]
        [ "$(/usr/bin/shasum -a 256 "$stage/bimeron-detach" | /usr/bin/cut -d ' ' -f 1)" = "$4" ]
        /bin/mv -f "$stage/bimeron-core" "$destination/bimeron-core"
        /bin/mv -f "$stage/bimeron-detach" "$destination/bimeron-detach"
        "$destination/bimeron-detach" "$5"
        """
}
