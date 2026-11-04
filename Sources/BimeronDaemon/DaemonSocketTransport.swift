import Foundation
#if os(macOS)
import Darwin
#endif

/// Each exchange owns one socket. No daemon installation or process ownership is implied.
public struct DaemonSocketTransport: Sendable {
    public init() {}

    public func exchange(_ request: DaemonRequest, timeout: Duration = .seconds(5)) async throws -> DaemonResponse {
        #if os(macOS)
        if request.command == "start" || request.command == "stop" {
            let hello = try await exchange(DaemonRequest(command: "hello"), timeout: timeout)
            try DaemonProtocol.authorizeMutation(request, hello: hello)
        }
        guard ["hello", "status", "start", "stop"].contains(request.command) else {
            throw DaemonError.invalidProtocol
        }
        let bytes = try DaemonProtocol.encode(request)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DaemonError.unavailable }
        defer { Darwin.close(fd) }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw DaemonError.unavailable }
        var noSignal: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw DaemonError.unavailable
        }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        func wait(_ events: Int16) async throws {
            while true {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw DaemonError.timeout }
                var descriptor = pollfd(fd: fd, events: events, revents: 0)
                let result = poll(&descriptor, 1, 0)
                if result > 0 { return }
                if result < 0 && errno != EINTR { throw DaemonError.unavailable }
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array("/var/run/bimeron/control.sock".utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: path.map { UInt8(bitPattern: $0) })
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            guard errno == EINPROGRESS else { throw DaemonError.unavailable }
            try await wait(Int16(POLLOUT))
            var error: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else {
                throw DaemonError.unavailable
            }
        }
        // Authenticate the connected peer before transmitting config paths or commands.
        var uid: uid_t = 1
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == 0 else { throw DaemonError.untrustedPeer }
        var offset = 0
        while offset < bytes.count {
            try await wait(Int16(POLLOUT))
            let count = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), bytes.count - offset) }
            if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            guard count > 0 else { throw DaemonError.unavailable }
            offset += count
        }
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            try await wait(Int16(POLLIN))
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            guard count > 0 else { throw DaemonError.invalidProtocol }
            response.append(contentsOf: buffer.prefix(count))
            guard response.count <= DaemonProtocol.responseLimit else { throw DaemonError.oversized }
            if response.contains(10) { return try DaemonProtocol.decode(response, request: request) }
        }
        #else
        throw DaemonError.unavailable
        #endif
    }
}
