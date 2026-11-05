import Darwin
import Foundation

@main
struct SelectionFreezeGate {
    static func owned(_ path: String, kind: mode_t, mode: mode_t) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == kind
            && info.st_mode & 0o7777 == mode && info.st_uid == getuid()
    }

    static func absent(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == -1 && errno == ENOENT
    }

    static func validationRoot(_ path: String, artifact: URL) -> URL? {
        let input = URL(fileURLWithPath: path)
        guard input.path == path, input.standardizedFileURL.path == path,
              input.resolvingSymlinksInPath().path == path,
              owned(path, kind: S_IFREG, mode: 0o600) else { return nil }
        let root = input.deletingLastPathComponent()
        let prefix = "bimeron-selection-gate-"
        let products = artifact.deletingLastPathComponent()
        guard root.deletingLastPathComponent().path == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path,
              !artifact.path.hasPrefix(root.path + "/"),
              root.path != products.path, !root.path.hasPrefix(products.path + "/"),
              root.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil,
              owned(root.path, kind: S_IFDIR, mode: 0o700) else { return nil }
        let marker = root.appending(path: ".selection-freeze-gate.owner")
        let token = Data("bimeron-selection-gate-owner-v1\n".utf8)
        var markerInfo = stat()
        guard owned(marker.path, kind: S_IFREG, mode: 0o600),
              lstat(marker.path, &markerInfo) == 0, markerInfo.st_size == token.count else { return nil }
        let fd = open(marker.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var bytes = [UInt8](repeating: 0, count: 64)
        let count = read(fd, &bytes, bytes.count)
        // This public test token identifies fixture ownership; it is not an OS security boundary.
        guard count >= 0, Data(bytes.prefix(count)) == token else { return nil }
        return root
    }

    static func main() {
        exit(run())
    }

    static func run() -> Int32 {
        let arguments = CommandLine.arguments
        if arguments.count == 2 && arguments[1] == "version" {
            print(#"{"version":"future-unknown","modified":false,"go_version":"unknown","platform":"darwin","architecture":"unknown"}"#)
            return 0
        }
        if arguments.count == 2 && arguments[1] == "capabilities" {
            print(#"{"platform":"darwin","vpn":false,"proxy":false,"ipv4":false,"ipv6":false,"ip_split":false,"domain_split":false,"app_split":false,"kill_switch":false,"daemon":false,"ikev2":{"administrator_required":false,"supported":false,"foreground_only":false,"preconfigured_profile":false,"proxy":false,"ip_split":false,"domain_split":false,"kill_switch":false,"dns_protection":false,"stats":false}}"#)
            return 0
        }
        guard arguments.count == 3, arguments[1] == "validate" else { return 9 }
        let artifact = URL(fileURLWithPath: arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        guard let root = validationRoot(arguments[2], artifact: artifact) else { return 9 }
        let started = root.appending(path: ".selection-freeze-gate.started").path
        let release = root.appending(path: ".selection-freeze-gate.release").path
        let reject = root.appending(path: ".selection-freeze-gate.reject").path
        guard [started, release, reject].allSatisfy({ $0.utf8.count < Int(PATH_MAX) }) else { return 9 }
        guard [release, reject].allSatisfy({ absent($0) || owned($0, kind: S_IFREG, mode: 0o600) }) else { return 9 }
        // Exercise CoreCLI's escalation and reap path when validation is cancelled.
        var action = sigaction()
        action.__sigaction_u.__sa_handler = SIG_IGN
        guard sigemptyset(&action.sa_mask) == 0, sigaction(SIGTERM, &action, nil) == 0 else { return 9 }
        do { try FileHandle.standardOutput.write(contentsOf: Data("\(getpid())\n".utf8)) }
        catch { return 9 }
        let descriptor = open(started, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { return 9 }
        guard close(descriptor) == 0 else { return 9 }
        while !owned(release, kind: S_IFREG, mode: 0o600) {
            guard absent(release) || owned(release, kind: S_IFREG, mode: 0o600),
                  absent(reject) || owned(reject, kind: S_IFREG, mode: 0o600) else { return 9 }
            var delay = timespec(tv_sec: 0, tv_nsec: 10_000_000)
            var remaining = timespec()
            while nanosleep(&delay, &remaining) != 0 {
                if errno != EINTR { return 9 }
                delay = remaining
            }
        }
        guard absent(reject) || owned(reject, kind: S_IFREG, mode: 0o600) else { return 9 }
        return owned(reject, kind: S_IFREG, mode: 0o600) ? 7 : 0
    }
}
