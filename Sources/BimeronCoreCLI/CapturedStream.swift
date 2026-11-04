import Foundation
import Darwin

struct CapturedStream {
    let fd: Int32
    let limit: Int
    var data = Data()
    var truncated = false
    var eof = false

    func makeNonblocking() throws {
        let flags = fcntl(fd, F_GETFL)
        guard flags != -1, fcntl(fd, F_SETFL, flags | O_NONBLOCK) != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    mutating func drain() throws {
        var buffer = [UInt8](repeating: 0, count: 8192)
        // Bound each pass so a continuously writing child cannot starve cancellation or the other stream.
        for _ in 0..<16 {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { eof = true; return }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            let kept = min(count, limit - data.count)
            data.append(contentsOf: buffer.prefix(kept))
            truncated = truncated || kept < count
        }
    }
}
