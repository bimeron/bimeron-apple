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
        let command = script(binaries: binaries, manifest: manifest, uid: getuid())
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
            process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw String(decoding: data, as: UTF8.self).contains("(-128)") ? Failure.cancelled : Failure.failed
            }
        }.value
    }

    static func verifyPayloads(binaries: URL, manifest: BundledCoreManifest) throws {
        for (name, expected) in [("bimeron-core", manifest.sha256), ("bimeron-detach", manifest.detach_sha256)] {
            let digest = SHA256.hash(data: try Data(contentsOf: binaries.appending(path: name)))
                .map { String(format: "%02x", $0) }.joined()
            guard digest == expected else { throw Failure.failed }
        }
    }

    static func script(binaries: URL, manifest: BundledCoreManifest, uid: UInt32) -> String {
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return """
        set -eu
        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        export PATH
        cd /
        protected() {
          [ ! -L "$1" ] && [ -d "$1" ]
          [ "$(/usr/bin/stat -f %u:%g "$1")" = 0:0 ]
          mode=$(/usr/bin/stat -f %Lp "$1")
          [ $((0$mode & 0022)) -eq 0 ]
          [ "$(/bin/ls -lde "$1" | /usr/bin/wc -l | /usr/bin/tr -d ' ')" = 1 ]
        }
        for dir in / /Library '/Library/Application Support'; do protected "$dir"; done
        for dir in '/Library/Application Support/Bimeron' '/Library/Application Support/Bimeron/DevCore'; do
          if [ ! -e "$dir" ] && [ ! -L "$dir" ]; then /bin/mkdir -m 0755 "$dir"; fi
          protected "$dir"
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
        /usr/bin/install -o root -g wheel -m 0755 \(quote(binaries.appending(path: "bimeron-core").path)) "$stage/bimeron-core"
        /usr/bin/install -o root -g wheel -m 0755 \(quote(binaries.appending(path: "bimeron-detach").path)) "$stage/bimeron-detach"
        [ "$(/usr/bin/shasum -a 256 "$stage/bimeron-core" | /usr/bin/cut -d ' ' -f 1)" = '\(manifest.sha256)' ]
        [ "$(/usr/bin/shasum -a 256 "$stage/bimeron-detach" | /usr/bin/cut -d ' ' -f 1)" = '\(manifest.detach_sha256)' ]
        /bin/mv -f "$stage/bimeron-core" "$destination/bimeron-core"
        /bin/mv -f "$stage/bimeron-detach" "$destination/bimeron-detach"
        "$destination/bimeron-detach" \(uid)
        """
    }
}
