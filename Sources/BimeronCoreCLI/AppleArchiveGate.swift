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

    private enum ZIPHeaderError: Error { case endOfFile }

    private struct ZIPEntry {
        let name: Data
        let creator, flags, method, attributes: Int
        let crc, compressed, size: UInt64
        let local, next: Int
    }

    // Only structural errors end Go's directory scan; policy checks run afterwards.
    private static func entry(_ b: Bytes, at p: Int) throws -> ZIPEntry {
        _ = try b.slice(p, 46)
        try require(try b.number(p, 4) == 0x02014b50)
        let nameSize = try b.int(p + 28, 2), extraSize = try b.int(p + 30, 2), commentSize = try b.int(p + 32, 2)
        if p + 46 == b.count && nameSize + extraSize + commentSize > 0 { throw ZIPHeaderError.endOfFile }
        _ = try b.slice(p + 46, nameSize + extraSize + commentSize)
        var size = try b.number(p + 24, 4), compressed = try b.number(p + 20, 4), local = try b.number(p + 42, 4)
        var needSize = size == 0xffffffff, needCompressed = compressed == 0xffffffff, needLocal = local == 0xffffffff
        let extra = Bytes(data: try b.slice(p + 46 + nameSize, extraSize))
        var x = 0
        while x + 4 <= extra.count {
            let kind = try extra.number(x, 2), length = try extra.int(x + 2, 2)
            guard length <= extra.count - x - 4 else { break }
            if kind == 1 {
                let field = Bytes(data: try extra.slice(x + 4, length))
                var q = 0
                if needSize { size = try field.number(q, 8); q += 8; needSize = false }
                if needCompressed { compressed = try field.number(q, 8); q += 8; needCompressed = false }
                if needLocal { local = try field.number(q, 8); needLocal = false }
            }
            x += 4 + length
        }
        // Go permits an unresolved ZIP32 uncompressed size, but not size/offset needed for reading.
        try require(!needCompressed && !needLocal)
        return try ZIPEntry(name: b.slice(p + 46, nameSize), creator: b.int(p + 5, 1),
            flags: b.int(p + 8, 2), method: b.int(p + 10, 2), attributes: b.int(p + 38, 4),
            crc: b.number(p + 16, 4), compressed: compressed, size: size,
            local: Int(truncatingIfNeeded: local), next: p + 46 + nameSize + extraSize + commentSize)
    }

    // Go's Mode.Type excludes setuid/setgid/sticky; unknown Unix type values map to regular.
    static func entryMode(creator: Int, attributes: Int, name: String) -> (regular: Bool, directory: Bool, permissions: Int) {
        var directory = false, special = false, permissions = 0
        switch creator {
        case 3, 19:
            let unix = attributes >> 16
            permissions = unix & 0o777
            switch unix & 0xf000 {
            case 0x4000: directory = true
            case 0x1000, 0x2000, 0x6000, 0xa000, 0xc000: special = true
            default: break
            }
        case 0, 11, 14:
            directory = attributes & 0x10 != 0
            permissions = directory ? 0o777 : 0o666
            if attributes & 1 != 0 { permissions &= ~0o222 }
        default: break
        }
        directory = directory || name.hasSuffix("/")
        return (!directory && !special, directory && !special, permissions)
    }

    static func check(_ data: Data, architecture: String, revision: String, version: String) throws {
        let b = Bytes(data: data)
        guard b.count >= 22 else { throw AppleCoreReleaseError.invalidArchive }
        var end: Int?
        // Match Go's two bounded search windows and its truncated-comment stop rule.
        for window in [1024, 65 * 1024] {
            for p in stride(from: b.count - 22, through: max(0, b.count - window), by: -1) {
                if try b.number(p, 4) == 0x06054b50 {
                    if try b.int(p + 20, 2) <= b.count - p - 22 { end = p }
                    break
                }
            }
            if end != nil || window >= b.count { break }
        }
        guard let end else { throw AppleCoreReleaseError.invalidArchive }
        var records = try b.number(end + 10, 2)
        var directorySize = try b.number(end + 12, 4), directoryOffset = try b.number(end + 16, 4)
        var directoryEnd = end
        // These sentinel values deliberately match pinned Go, including its 0xffff size test.
        if records == 0xffff || directorySize == 0xffff || directoryOffset == 0xffffffff {
            let locator = end - 20
            if locator >= 0, try b.number(locator, 4) == 0x07064b50,
               try b.number(locator + 4, 4) == 0, try b.number(locator + 16, 4) == 1,
               let zip64 = Int(exactly: try b.number(locator + 8, 8)) {
                _ = try b.slice(zip64, 56)
                try require(try b.number(zip64, 4) == 0x06064b50)
                records = try b.number(zip64 + 32, 8)
                directorySize = try b.number(zip64 + 40, 8)
                directoryOffset = try b.number(zip64 + 48, 8)
                directoryEnd = zip64
            }
        }
        guard let size = Int(exactly: directorySize), let offset = Int(exactly: directoryOffset) else {
            throw AppleCoreReleaseError.invalidArchive
        }
        // Go int64 offset arithmetic wraps; all resulting byte ranges still require bounds checks.
        var base = directoryEnd &- size &- offset
        var p = base &+ offset
        try require(p >= 0 && p < b.count)
        if base > 0, (try? entry(b, at: offset)) != nil { base = 0; p = offset }
        var entries: [ZIPEntry] = []
        while entries.count <= 4 {
            // readDirectoryHeader returns EOF (not its accepted UnexpectedEOF) at exact file end.
            try require(p != b.count)
            do {
                let next = try entry(b, at: p)
                entries.append(next)
                p = next.next
            } catch ZIPHeaderError.endOfFile {
                throw AppleCoreReleaseError.invalidArchive
            } catch { break }
        }
        try require((3...4).contains(entries.count) && UInt64(entries.count) == (records & 0xffff))
        let parent = "macos-\(architecture)/"
        var seen = Set<String>()
        for entry in entries {
            guard let name = String(data: entry.name, encoding: .utf8) else { throw AppleCoreReleaseError.invalidArchive }
            let flags = entry.flags, method = entry.method, crc = entry.crc
            try require(seen.insert(name).inserted && flags & 1 == 0 && [0, 8].contains(method))
            let mode = entryMode(creator: entry.creator, attributes: entry.attributes, name: name)
            if name == parent {
                try require(mode.directory && entry.size == 0)
            } else {
                try require([parent + "bimeron", parent + "LICENSE", parent + "THIRD_PARTY_NOTICES.txt"].contains(name))
                try require(mode.regular && entry.size > 0 && entry.size <= (name == parent + "bimeron" ? 268_435_456 : 4_194_304))
                if name == parent + "bimeron" { try require(mode.permissions & 0o111 != 0) }
            }
            // Core skips directory payloads. Local names/flags/methods never select paths or decoding.
            if name != parent {
                guard let size = Int(exactly: entry.size) else { throw AppleCoreReleaseError.invalidArchive }
                let compressed = Int(truncatingIfNeeded: entry.compressed)
                let local = entry.local &+ base
                _ = try b.slice(local, 30)
                try require(try b.number(local, 4) == 0x04034b50)
                let localNameSize = try b.int(local + 26, 2), localExtra = try b.int(local + 28, 2)
                let payloadOffset = local + 30 + localNameSize + localExtra
                try require(payloadOffset <= b.count)
                // Match io.NewSectionReader's signed limit arithmetic, capped by authenticated bytes.
                let limit = payloadOffset <= (Int.max &- compressed) ? (payloadOffset &+ compressed) : Int.max
                let readable = limit > payloadOffset ? min(b.count - payloadOffset, limit - payloadOffset) : 0
                let payload = try b.slice(payloadOffset, readable)
                let contents = try inflate(payload, size: size, method: method)
                let actualCRC = contents.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(contents.count)) }
                if flags & 8 != 0 {
                    // archive/zip.readDataDescriptor consumes 12 bytes, or 16 with signature.
                    // Its size words are ignored, including ZIP64 descriptors; central sizes govern.
                    let descriptor = payloadOffset &+ compressed
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
        }
        try require(["bimeron", "LICENSE", "THIRD_PARTY_NOTICES.txt"].allSatisfy { seen.contains(parent + $0) })
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
        // Go flate stops at the final block; unused bytes inside the bounded payload are ignored.
        try require(status == Z_STREAM_END && stream.total_out == size)
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
