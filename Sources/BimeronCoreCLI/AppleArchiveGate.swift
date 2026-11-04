import CZlib
import Foundation

// All offsets originate in authenticated but still hostile bytes. Never load native structs.
private struct Bytes {
    let data: Data
    var count: Int { data.count }
    func slice(_ offset: Int, _ size: Int) throws -> Data {
        guard offset >= 0, size >= 0, offset <= count, size <= count - offset else { throw AppleCoreReleaseError.invalidArchive }
        return data.subdata(in: offset..<offset + size)
    }
    func number(_ offset: Int, _ size: Int) throws -> UInt64 {
        try slice(offset, size).enumerated().reduce(0) { $0 | UInt64($1.element) << ($1.offset * 8) }
    }
    func int(_ offset: Int, _ size: Int) throws -> Int {
        guard let value = Int(exactly: try number(offset, size)) else { throw AppleCoreReleaseError.invalidArchive }
        return value
    }
    func name(_ offset: Int) throws -> String {
        String(decoding: try slice(offset, 16).prefix(while: { $0 != 0 }), as: UTF8.self)
    }
}

enum AppleArchiveGate {
    private static func require(_ condition: Bool) throws {
        guard condition else { throw AppleCoreReleaseError.invalidArchive }
    }

    static func check(_ data: Data, architecture: String, revision: String, version: String) throws {
        let b = Bytes(data: data)
        // EOCD may have a bounded ZIP comment; ZIP64 fields keep the same size limits.
        guard b.count >= 22 else { throw AppleCoreReleaseError.invalidArchive }
        var end: Int?
        for p in stride(from: b.count - 22, through: max(0, b.count - 65_557), by: -1) {
            if try b.number(p, 4) == 0x06054b50, try p + 22 + b.int(p + 20, 2) == b.count { end = p; break }
        }
        guard let end else { throw AppleCoreReleaseError.invalidArchive }
        var count = try b.int(end + 10, 2)
        try require(try b.number(end + 4, 4) == 0 && b.int(end + 8, 2) == count)
        var p = try b.int(end + 16, 4)
        var directorySize = try b.int(end + 12, 4)
        var directoryEnd = end
        if count == 65535 || p == 0xffffffff || directorySize == 0xffffffff {
            let locator = end - 20
            try require(try b.number(locator, 4) == 0x07064b50 && b.number(locator + 4, 4) == 0 && b.number(locator + 16, 4) == 1)
            let zip64 = try b.int(locator + 8, 8)
            try require(try b.number(zip64, 4) == 0x06064b50 && b.number(zip64 + 4, 8) >= 44 && b.number(zip64 + 16, 8) == 0)
            count = try b.int(zip64 + 32, 8)
            try require(try b.int(zip64 + 24, 8) == count)
            p = try b.int(zip64 + 48, 8)
            directorySize = try b.int(zip64 + 40, 8)
            directoryEnd = zip64
        }
        try require((3...4).contains(count) && p <= directoryEnd && directorySize == directoryEnd - p)
        let parent = "macos-\(architecture)/"
        var seen = Set<String>()
        for _ in 0..<count {
            try require(try b.number(p, 4) == 0x02014b50)
            let creator = try b.int(p + 5, 1), flags = try b.int(p + 8, 2), method = try b.int(p + 10, 2)
            let crc = try b.number(p + 16, 4)
            var compressed = try b.int(p + 20, 4), size = try b.int(p + 24, 4)
            let nameSize = try b.int(p + 28, 2), extra = try b.int(p + 30, 2), comment = try b.int(p + 32, 2)
            let attributes = try b.int(p + 38, 4)
            var local = try b.int(p + 42, 4)
            let extraBytes = Bytes(data: try b.slice(p + 46 + nameSize, extra))
            var x = 0
            while x + 4 <= extraBytes.count {
                let kind = try extraBytes.number(x, 2), length = try extraBytes.int(x + 2, 2)
                guard length <= extraBytes.count - x - 4 else { break }
                if kind == 1 {
                    var q = x + 4
                    if size == 0xffffffff { size = try extraBytes.int(q, 8); q += 8 }
                    if compressed == 0xffffffff { compressed = try extraBytes.int(q, 8); q += 8 }
                    if local == 0xffffffff { local = try extraBytes.int(q, 8); q += 8 }
                    try require(q <= x + 4 + length)
                }
                x += 4 + length
            }
            let nameBytes = try b.slice(p + 46, nameSize)
            guard let name = String(data: nameBytes, encoding: .utf8) else { throw AppleCoreReleaseError.invalidArchive }
            try require(seen.insert(name).inserted && flags & 1 == 0 && [0, 8].contains(method) && b.number(p + 34, 2) == 0)
            let mode = creator == 3 || creator == 19 ? attributes >> 16 : 0
            let isDirectory = name.hasSuffix("/")
            if name == parent {
                try require(isDirectory && size == 0 && (mode & 0xf000 == 0x4000 || mode & 0xf000 == 0))
            } else {
                try require([parent + "bimeron", parent + "LICENSE", parent + "THIRD_PARTY_NOTICES.txt"].contains(name))
                try require(!isDirectory && (mode & 0xf000 == 0x8000 || mode & 0xf000 == 0) && attributes & 0x10 == 0)
                try require(size > 0 && size <= (name == parent + "bimeron" ? 268_435_456 : 4_194_304))
                if name == parent + "bimeron" { try require(mode & 0o111 != 0) }
            }
            // Core skips directory payloads. Local names/flags/methods never select paths or decoding.
            if name != parent {
                _ = try b.slice(local, 30)
                try require(try b.number(local, 4) == 0x04034b50)
                let localNameSize = try b.int(local + 26, 2), localExtra = try b.int(local + 28, 2)
                let payloadOffset = local + 30 + localNameSize + localExtra
                let payload = try b.slice(payloadOffset, compressed)
                let contents = try inflate(payload, size: size, method: method)
                let actualCRC = contents.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(contents.count)) }
                if flags & 8 != 0 {
                    // archive/zip.readDataDescriptor consumes 12 bytes, or 16 with signature.
                    // Its size words are ignored, including ZIP64 descriptors; central sizes govern.
                    let descriptor = payloadOffset + compressed
                    let signed = try b.number(descriptor, 4) == 0x08074b50
                    let crcOffset = descriptor + (signed ? 4 : 0)
                    _ = try b.slice(crcOffset, 12)
                    try require(try b.number(crcOffset, 4) == crc)
                    try require(UInt64(actualCRC) == crc)
                } else if crc != 0 {
                    try require(UInt64(actualCRC) == crc)
                }
                if name == parent + "bimeron" { try binary(contents, architecture: architecture, revision: revision, version: version) }
            }
            p += 46 + nameSize + extra + comment
            try require(p <= directoryEnd)
        }
        try require(p == directoryEnd && ["bimeron", "LICENSE", "THIRD_PARTY_NOTICES.txt"].allSatisfy { seen.contains(parent + $0) })
    }

    private static func inflate(_ input: Data, size: Int, method: Int) throws -> Data {
        if method == 0 { try require(input.count == size); return input }
        var stream = z_stream()
        try require(inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK)
        defer { inflateEnd(&stream) }
        var output = Data(count: max(1, size))
        let status = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { target in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = target.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(max(1, size))
                return CZlib.inflate(&stream, Z_FINISH)
            }
        }
        try require(status == Z_STREAM_END && stream.total_out == size && stream.total_in == input.count)
        return output.prefix(size)
    }

    static func record(_ data: Data) throws -> String {
        try require(data.count <= 64 * 1024 * 1024)
        let prefix = Data("BIMERON.APPLE.CORE.VERSION/v1\0".utf8)
        guard let range = data.range(of: prefix) else { throw AppleCoreReleaseError.invalidArchive }
        try require(data.range(of: prefix, in: range.upperBound..<data.endIndex) == nil)
        let b = Bytes(data: data), p = range.upperBound
        let digits = try b.slice(p, 3)
        try require(digits.allSatisfy { (48...57).contains($0) } && b.number(p + 3, 1) == 58)
        let size = digits.reduce(0) { $0 * 10 + Int($1 - 48) }
        try require((1...128).contains(size))
        guard let version = String(data: try b.slice(p + 4, size), encoding: .utf8), AppleCoreRelease.validCoreVersion(version) else { throw AppleCoreReleaseError.invalidArchive }
        let suffix = Data("\0END.APPLE.CORE.RECORD/v1\0".utf8)
        try require(try b.slice(p + 4 + size, suffix.count) == suffix)
        return version
    }

    static func binary(_ data: Data, architecture: String, revision: String, version: String) throws {
        let b = Bytes(data: data)
        try require(try b.number(0, 4) == 0xfeedfacf && b.number(4, 4) == (architecture == "arm64" ? 0x100000c : 0x1000007) && b.number(12, 4) == 2)
        let commands = try b.int(16, 4), commandSize = try b.int(20, 4)
        _ = try b.slice(32, commandSize)
        try require(commands <= commandSize / 8)
        var p = 32, textCount = 0, records: [Data] = [], buildSections: [Data] = []
        for _ in 0..<commands {
            let cmd = try b.number(p, 4), size = try b.int(p + 4, 4)
            try require(size >= 8 && size <= 32 + commandSize - p)
            if cmd == 0x19 {
                try require(size >= 72)
                let segment = try b.name(p + 8), address = try b.number(p + 24, 8), memorySize = try b.number(p + 32, 8)
                let offset = try b.number(p + 40, 8), fileSize = try b.number(p + 48, 8), prot = try b.number(p + 60, 4)
                let sections = try b.int(p + 64, 4)
                try require(sections <= (size - 72) / 80)
                if segment == "__TEXT" { textCount += 1 }
                for i in 0..<sections {
                    let s = p + 72 + i * 80
                    let name = try b.name(s), seg = try b.name(s + 16)
                    if seg == "__TEXT" && name == "__rodata" || name == "__go_buildinfo" {
                        let addr = try b.number(s + 32, 8), length = try b.number(s + 40, 8), off = try b.number(s + 48, 4)
                        try require(offset <= b.count && fileSize <= UInt64(b.count) - offset && fileSize <= memorySize && off >= offset && off - offset <= fileSize && length <= fileSize - (off - offset) && addr >= address && addr - address <= memorySize && length <= memorySize - (addr - address) && addr - address == off - offset)
                        if seg == "__TEXT" && name == "__rodata" {
                            try require(segment == "__TEXT" && prot & 2 == 0 && prot & 1 != 0 && length <= 64 * 1024 * 1024)
                            records.append(try b.slice(Int(off), Int(length)))
                        }
                        if name == "__go_buildinfo" { buildSections.append(try b.slice(Int(off), Int(length))) }
                    }
                }
            }
            p += size
        }
        try require(p == 32 + commandSize && textCount == 1 && records.count == 1 && buildSections.count == 1)
        try require(try record(records[0]) == version)
        try buildInfo(buildSections[0], architecture: architecture, revision: revision)
    }

    private static func buildInfo(_ data: Data, architecture: String, revision: String) throws {
        let b = Bytes(data: data)
        try require(try b.slice(0, 14) == Data([255]) + Data(" Go buildinf:".utf8) && b.number(14, 1) == 8 && b.number(15, 1) == 2)
        var p = 32
        func string() throws -> Data {
            var length: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                let byte = try b.number(p, 1); p += 1
                try require(shift != 63 || byte <= 1)
                length |= (byte & 127) << shift
                if byte < 128 {
                    try require(length <= b.count)
                    let result = try b.slice(p, Int(length)); p += Int(length); return result
                }
            }
            throw AppleCoreReleaseError.invalidArchive
        }
        try require(!(try string()).isEmpty)
        let framed = try string()
        try require(framed.count >= 33 && framed[framed.count - 17] == 10)
        guard let module = String(data: framed.dropFirst(16).dropLast(16), encoding: .utf8) else { throw AppleCoreReleaseError.invalidArchive }
        var settings: [String: String] = [:]
        var lastModule = false
        // Match runtime/debug.ParseBuildInfo's line and quoting rules.
        for line in module.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
            if line.hasPrefix("mod\t") || line.hasPrefix("dep\t") {
                try require([2, 3].contains(line.dropFirst(4).split(separator: "\t", omittingEmptySubsequences: false).count))
                lastModule = true
            } else if line.hasPrefix("=>\t") {
                try require(lastModule && line.dropFirst(3).split(separator: "\t", omittingEmptySubsequences: false).count == 3)
                lastModule = false
            } else if line.hasPrefix("build\t") {
                let bytes = Array(line.dropFirst(6).utf8)
                var position = 0
                let key: String
                if bytes.first == 34 || bytes.first == 96 {
                    key = try goQuoted(bytes, position: &position)
                    try require(position < bytes.count && bytes[position] == 61)
                } else {
                    guard let equal = bytes.firstIndex(of: 61) else { throw AppleCoreReleaseError.invalidArchive }
                    key = String(decoding: bytes[..<equal], as: UTF8.self)
                    try require(!key.isEmpty && !key.contains(where: { "= \t\r\n\"`".contains($0) }))
                    position = equal
                }
                position += 1
                let value: String
                if position < bytes.count && [34, 96].contains(bytes[position]) {
                    value = try goQuoted(bytes, position: &position)
                    try require(position == bytes.count)
                } else {
                    value = String(decoding: bytes[position...], as: UTF8.self)
                    try require(!value.contains(where: { " \t\r\n\"`".contains($0) }))
                }
                try require(settings.updateValue(value, forKey: key) == nil)
            }
        }
        for (key, value) in ["GOOS": "darwin", "GOARCH": architecture, "vcs": "git", "vcs.revision": revision, "vcs.modified": "false", "-trimpath": "true"] {
            try require(settings[key] == value)
        }
    }

    private static func goQuoted(_ bytes: [UInt8], position: inout Int) throws -> String {
        let quote = bytes[position]; position += 1
        var result: [UInt8] = []
        while position < bytes.count {
            let c = bytes[position]; position += 1
            if c == quote {
                guard let string = String(bytes: result, encoding: .utf8) else { throw AppleCoreReleaseError.invalidArchive }
                return string
            }
            if quote == 96 { if c != 13 { result.append(c) }; continue }
            try require(c != 10)
            if c != 92 { result.append(c); continue }
            try require(position < bytes.count)
            let escaped = bytes[position]; position += 1
            let escapes: [UInt8: UInt8] = [97: 7, 98: 8, 102: 12, 110: 10, 114: 13, 116: 9, 118: 11, 92: 92, 34: 34]
            if let value = escapes[escaped] { result.append(value); continue }
            let digits: Int, base: UInt32
            switch escaped {
            case 120: digits = 2; base = 16
            case 117: digits = 4; base = 16
            case 85: digits = 8; base = 16
            case 48...55: digits = 3; base = 8; position -= 1
            default: throw AppleCoreReleaseError.invalidArchive
            }
            try require(digits <= bytes.count - position)
            var value: UInt32 = 0
            for _ in 0..<digits {
                let digit = bytes[position]; position += 1
                let n: UInt32
                switch digit {
                case 48...57: n = UInt32(digit - 48)
                case 65...70: n = UInt32(digit - 55)
                case 97...102: n = UInt32(digit - 87)
                default: throw AppleCoreReleaseError.invalidArchive
                }
                try require(n < base)
                value = value * base + n
            }
            if escaped == 117 || escaped == 85 {
                guard let scalar = UnicodeScalar(value) else { throw AppleCoreReleaseError.invalidArchive }
                result.append(contentsOf: String(scalar).utf8)
            } else {
                try require(value <= 255); result.append(UInt8(value))
            }
        }
        throw AppleCoreReleaseError.invalidArchive
    }

}
