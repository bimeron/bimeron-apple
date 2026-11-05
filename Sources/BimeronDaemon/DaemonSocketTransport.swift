import Foundation
#if os(macOS)
import Darwin
#endif

/// Each exchange owns one socket. No daemon installation or process ownership is implied.
public struct DaemonSocketTransport: Sendable {
    public init() {}

    public func exchange(_ request: DaemonRequest, timeout: Duration = .seconds(5)) async throws -> DaemonResponse {
        let data = try await framedExchange(request, timeout: timeout)
        return try DaemonProtocol.decode(data, request: request)
    }

    /// Suitable for injection into DaemonClient or the read-only statistics adapter.
    public func framedExchange(_ request: DaemonRequest, timeout: Duration = .seconds(5)) async throws -> Data {
        let deadline = DaemonSocketDeadline(timeout: timeout)
        try deadline.check()
        guard ["hello", "status", "stats_snapshot", "events", "start", "stop"].contains(request.command) else {
            throw DaemonError.invalidProtocol
        }
        if request.command == "start" || request.command == "stop" {
            let helloRequest = DaemonRequest(command: "hello")
            let data = try await receive(helloRequest, deadline: deadline)
            let hello = try DaemonProtocol.decode(data, request: helloRequest)
            try DaemonProtocol.authorizeMutation(request, hello: hello)
        }
        return try await receive(request, deadline: deadline)
    }

    private func receive(_ request: DaemonRequest, deadline: DaemonSocketDeadline) async throws -> Data {
        try deadline.check()
        #if os(macOS)
        let bytes = try DaemonProtocol.encode(request)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DaemonError.unavailable }
        defer { Darwin.close(fd) }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw DaemonError.unavailable }
        var noSignal: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw DaemonError.unavailable
        }
        func wait(_ events: Int16) async throws {
            while true {
                try deadline.check()
                var descriptor = pollfd(fd: fd, events: events, revents: 0)
                let result = poll(&descriptor, 1, 0)
                if result > 0 { return }
                if result < 0 && errno != EINTR { throw DaemonError.unavailable }
                try await ContinuousClock().sleep(until: min(deadline.instant, ContinuousClock.now.advanced(by: .milliseconds(5))))
            }
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array("/var/run/bimeron/control.sock".utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: path.map { UInt8(bitPattern: $0) })
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        try deadline.check()
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
        try deadline.check()
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
        var response = DaemonSocketResponseBuffer()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            try await wait(Int16(POLLIN))
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            guard count > 0 else { throw DaemonError.invalidProtocol }
            if let data = try response.append(buffer.prefix(count), request: request) {
                try deadline.check()
                return data
            }
        }
        #else
        throw DaemonError.unavailable
        #endif
    }
}

/// Shared by the mutation handshake and command; wall-clock changes cannot extend it.
struct DaemonSocketDeadline: Sendable {
    let instant: ContinuousClock.Instant

    init(timeout: Duration, now: ContinuousClock.Instant = .now) {
        instant = now.advanced(by: timeout)
    }

    func check(now: ContinuousClock.Instant = .now) throws {
        try Task.checkCancellation()
        guard now < instant else { throw DaemonError.timeout }
    }
}

struct DaemonSocketResponseBuffer {
    private(set) var data = Data()

    mutating func append(_ bytes: ArraySlice<UInt8>, request: DaemonRequest) throws -> Data? {
        guard bytes.count <= DaemonProtocol.responseLimit - data.count else { throw DaemonError.oversized }
        data.append(contentsOf: bytes)
        if bytes.contains(10) {
            _ = try DaemonProtocol.decode(data, request: request)
            return data
        }
        guard data.count < DaemonProtocol.responseLimit else { throw DaemonError.oversized }
        return nil
    }
}
