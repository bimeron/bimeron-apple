import Foundation
import Darwin

/// Keeps source lines intact. Form edits replace only the field the user edited.
public struct ConfigDocument: Equatable, Sendable {
    public static let sizeLimit = 65_536
    private var lines: [String]

    public init(_ text: String) throws {
        guard text.utf8.count <= Self.sizeLimit else { throw ProfileError.tooLarge }
        let clean = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        lines = clean.replacing("\r\n", with: "\n").components(separatedBy: "\n")
        try checkSyntax()
    }

    public init(data: Data) throws {
        guard data.count <= Self.sizeLimit else { throw ProfileError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw ProfileError.invalidUTF8 }
        try self.init(text)
    }

    public var text: String { lines.joined(separator: "\n") }
    public var name: String { value("Profile", "Name") ?? "" }
    public var mode: String { value("Interface", "Mode") ?? "vpn" }
    private static let sourceKeys = AccessProtocol.allCases.map(\.rawValue) + ["Key", "File"]
    public var source: String {
        for key in Self.sourceKeys {
            if value("AccessKey", key) != nil { return key }
        }
        return value("AccessKey", "Type") ?? "explicit"
    }
    public var accessKey: String { value("AccessKey", source) ?? "" }
    public var isExplicit: Bool { value("AccessKey", "Type") != nil }
    public var accessProtocol: AccessProtocol? {
        if let type = value("AccessKey", "Type") { return AccessProtocol(explicitType: type) }
        if source == "Key" { return AccessProtocol(key: accessKey) }
        return AccessProtocol(rawValue: source)
    }
    public var protocolName: String { accessProtocol?.title ?? "Config" }

    public static func protocolName(for key: String) -> String {
        AccessProtocol(key: key)?.title ?? "Config"
    }

    public static func new(name: String, key: String) throws -> Self {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateKey(key)
        var doc = try Self("[Profile]\nVersion = 1\n\n[AccessKey]\n\n[Interface]\nMode = vpn\nName = Bimeron\nMTU = 1420\nDNS = 1.1.1.1\nIPv6 = disable\nKillSwitch = false\n\n[Routing]\nDefault = proxy\n")
        doc.set("Profile", "Name", name)
        let source = AccessProtocol(key: key)?.rawValue ?? "Key"
        doc.set("AccessKey", source, key)
        try doc.validateLocally()
        return doc
    }

    public static func suggestedName(for key: String) -> String? {
        guard let hash = key.firstIndex(of: "#") else { return nil }
        let value = String(key[key.index(after: hash)...]).removingPercentEncoding ?? ""
        let name = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
        return name.isEmpty ? nil : String(name.prefix(128))
    }

    public func value(_ section: String, _ key: String) -> String? {
        guard let range = sectionRange(section) else { return nil }
        for line in lines[range] {
            if let pair = try? Self.pair(line), pair.0 == key { return pair.1 }
        }
        return nil
    }

    public mutating func set(_ section: String, _ key: String, _ value: String) {
        let replacement = "\(key) = \(Self.encode(value))"
        if let range = sectionRange(section) {
            if let index = range.first(where: { (try? Self.pair(lines[$0]))?.0 == key }) {
                lines[index] = replacement
            } else {
                lines.insert(replacement, at: range.lowerBound + 1)
            }
        } else {
            lines.append(contentsOf: ["", "[\(section)]", replacement])
        }
    }

    public func hasSection(_ section: String) -> Bool { sectionRange(section) != nil }

    public mutating func remove(_ section: String, _ key: String) {
        guard let range = sectionRange(section),
              let index = range.first(where: { (try? Self.pair(lines[$0]))?.0 == key }) else { return }
        lines.remove(at: index)
    }

    public mutating func removeSection(_ section: String) {
        if let range = sectionRange(section) { lines.removeSubrange(range) }
    }

    public mutating func setMode(_ mode: String) {
        set("Interface", "Mode", mode)
        if mode == "proxy" {
            // Core rejects IPv6 blocking and kill switch protection in proxy mode.
            remove("Interface", "IPv6")
            remove("Interface", "KillSwitch")
        }
    }

    /// Preserve local file references when the imported profile moves into the library.
    public mutating func resolveFileReferences(relativeTo original: URL) {
        func absolute(_ path: String) -> String {
            let expanded = (path as NSString).expandingTildeInPath
            return expanded.hasPrefix("/") ? expanded : original.deletingLastPathComponent().appending(path: expanded).standardizedFileURL.path
        }
        for key in ["IdentityFile", "KnownHostsFile", "CAFile"] {
            if let path = value("AccessKey", key), !path.isEmpty { set("AccessKey", key, absolute(path)) }
        }
        // Overrides preserve the original SSH URI bytes, including percent encoding.
        if accessProtocol == .ssh, let url = URLComponents(string: accessKey) {
            for (query, key) in [("identity", "IdentityFile"), ("known_hosts", "KnownHostsFile")] {
                if value("AccessKey", key) == nil,
                   let path = url.queryItems?.first(where: { $0.name == query })?.value, !path.isEmpty {
                    set("AccessKey", key, absolute(path))
                }
            }
        }
    }

    public mutating func inlineFile(relativeTo original: URL) throws {
        guard let path = value("AccessKey", "File") else { return }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : original.deletingLastPathComponent().appending(path: path)
        let data: Data
        do { data = try Self.readLimited(url) }
        catch ProfileError.tooLarge { throw ProfileError.tooLarge }
        catch { throw ProfileError.unreadableKey }
        guard let string = String(data: data, encoding: .utf8) else { throw ProfileError.invalidUTF8 }
        let key = string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        try Self.validateKey(key)
        guard let range = sectionRange("AccessKey"), let index = range.first(where: { (try? Self.pair(lines[$0]))?.0 == "File" }) else { return }
        lines[index] = "Key = \(Self.encode(key))"
    }

    public static func readLimited(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: sizeLimit + 1) ?? Data()
        guard data.count <= sizeLimit else { throw ProfileError.tooLarge }
        return data
    }

    public func validateLocally() throws {
        guard text.utf8.count <= Self.sizeLimit else { throw ProfileError.tooLarge }
        try checkSyntax()
        guard value("Profile", "Version") == "1" else { throw ProfileError.invalid("Version") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 128, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw ProfileError.invalid("Name") }
        let sources = Self.sourceKeys.filter { value("AccessKey", $0) != nil }
        let explicit = value("AccessKey", "Type") != nil || value("AccessKey", "Server") != nil
        guard sources.count + (explicit ? 1 : 0) == 1 else { throw ProfileError.invalid("AccessKey") }
        // Managed profiles have no stable link to the original import directory.
        if sources.contains("File") { throw ProfileError.invalid("AccessKey.File") }
        if let source = sources.first, source != "File" {
            let key = value("AccessKey", source) ?? ""
            try Self.validateKey(key)
            if source != "Key", AccessProtocol(key: key)?.rawValue != source { throw ProfileError.invalid("AccessKey.\(source)") }
        }
        if explicit {
            guard let type = value("AccessKey", "Type"), AccessProtocol(explicitType: type) != nil else { throw ProfileError.invalid("AccessKey.Type") }
            guard !(value("AccessKey", "Server") ?? "").isEmpty else { throw ProfileError.missing("Server") }
            guard let port = Int(value("AccessKey", "Port") ?? ""), (1...65535).contains(port) else { throw ProfileError.invalid("Port") }
        }
        if let mtu = value("Interface", "MTU"), !(1280...1500).contains(Int(mtu) ?? 0) { throw ProfileError.invalid("MTU") }
        if let dns = value("Interface", "DNS") {
            let addresses = dns.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard (1...4).contains(addresses.count), Set(addresses).count == addresses.count else { throw ProfileError.invalid("DNS") }
            for address in addresses {
                var parsed = in_addr()
                guard inet_pton(AF_INET, address, &parsed) == 1, let first = address.split(separator: ".").first.flatMap({ Int($0) }), first > 0, first < 224, address != "255.255.255.255" else { throw ProfileError.invalid("DNS") }
            }
        }
        if let mode = value("Interface", "Mode"), !["vpn", "proxy"].contains(mode) { throw ProfileError.invalid("Mode") }
        if let ipv6 = value("Interface", "IPv6"), !["enable", "disable"].contains(ipv6) { throw ProfileError.invalid("IPv6") }
        if let kill = value("Interface", "KillSwitch"), !["true", "false"].contains(kill) { throw ProfileError.invalid("KillSwitch") }
        if let action = value("Routing", "Default"), !["proxy", "direct", "block"].contains(action) { throw ProfileError.invalid("Routing.Default") }
        if hasSection("ShadowTLS") {
            for key in ["ServerName", "Password"] {
                guard !(value("ShadowTLS", key) ?? "").isEmpty else { throw ProfileError.missing("ShadowTLS.\(key)") }
            }
        }
        for rule in rules {
            if !rule.enabled { continue }
            guard ["proxy", "direct", "block"].contains(rule.action), !rule.destination.trimmingCharacters(in: .whitespaces).isEmpty else { throw ProfileError.invalid("Rule") }
            if rule.type == "CIDR" {
                for part in rule.destination.split(separator: ",", omittingEmptySubsequences: false) {
                    let parts = part.trimmingCharacters(in: .whitespaces).split(separator: "/", omittingEmptySubsequences: false)
                    guard (1...2).contains(parts.count) else { throw ProfileError.invalid("CIDR") }
                    var ipv4 = in_addr(); var ipv6 = in6_addr()
                    let v4 = inet_pton(AF_INET, String(parts[0]), &ipv4) == 1
                    guard v4 || inet_pton(AF_INET6, String(parts[0]), &ipv6) == 1 else { throw ProfileError.invalid("CIDR") }
                    if parts.count == 2, !(0...(v4 ? 32 : 128)).contains(Int(parts[1]) ?? -1) { throw ProfileError.invalid("CIDR") }
                }
            } else if rule.destination.contains("*") || rule.destination.contains(where: { $0.isWhitespace }) {
                throw ProfileError.invalid("Domain")
            }
        }
    }

    public static func validateKey(_ key: String) throws {
        let scheme = key.components(separatedBy: "://")
        guard scheme.count >= 2, AccessProtocol(key: key) != nil,
              !scheme.dropFirst().joined(separator: "://").isEmpty,
              !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !key.contains(where: { $0.isWhitespace }) else { throw ProfileError.invalid("AccessKey") }
    }

    public var rules: [RoutingRule] {
        ruleRanges.enumerated().map { offset, range in
            let enabled = Self.header(lines[range.lowerBound]) == "Rule"
            let pairs = lines[range].compactMap { line -> (String, String)? in
                let clean = enabled ? line : Self.uncomment(line)
                return try? Self.pair(clean)
            }
            let values = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
            return RoutingRule(id: offset, enabled: enabled, type: values["CIDR"] == nil ? "Domain" : "CIDR", destination: values["CIDR"] ?? values["Domain"] ?? "", action: values["Action"] ?? "proxy")
        }
    }

    public mutating func updateRule(_ rule: RoutingRule) {
        guard ruleRanges.indices.contains(rule.id) else { return }
        let range = ruleRanges[rule.id]
        let wasEnabled = Self.header(lines[range.lowerBound]) == "Rule"
        var block = Array(lines[range]).map { wasEnabled ? $0 : Self.uncomment($0) }
        for (key, value) in [(rule.type, rule.destination), ("Action", rule.action)] {
            let candidates = key == "Action" ? ["Action"] : ["CIDR", "Domain"]
            if let index = block.indices.first(where: { candidates.contains((try? Self.pair(block[$0]))?.0 ?? "") }) {
                block[index] = "\(key) = \(Self.encode(value))"
            } else { block.append("\(key) = \(Self.encode(value))") }
        }
        if !rule.enabled { block = block.map { $0.isEmpty ? $0 : "# " + $0 } }
        lines.replaceSubrange(range, with: block)
    }

    public mutating func addRule() {
        lines.append(contentsOf: ["", "[Rule]", "Domain = example.com", "Action = proxy", ""])
    }

    public mutating func removeRule(_ index: Int) {
        guard ruleRanges.indices.contains(index) else { return }
        lines.removeSubrange(ruleRanges[index])
    }

    public mutating func moveRule(_ index: Int, by offset: Int) {
        let ranges = ruleRanges
        let other = index + offset
        guard ranges.indices.contains(index), ranges.indices.contains(other), abs(offset) == 1 else { return }
        let low = min(index, other), high = max(index, other)
        let lowBlock = Array(lines[ranges[low]]), highBlock = Array(lines[ranges[high]])
        lines.replaceSubrange(ranges[high], with: lowBlock)
        lines.replaceSubrange(ranges[low], with: highBlock)
    }

    private var ruleRanges: [Range<Int>] {
        let starts = lines.indices.filter { Self.header(lines[$0]) != nil || Self.header(Self.uncomment(lines[$0])) == "Rule" }
        return starts.enumerated().compactMap { offset, start in
            guard Self.header(lines[start]) == "Rule" || Self.header(Self.uncomment(lines[start])) == "Rule" else { return nil }
            return start..<(offset + 1 < starts.count ? starts[offset + 1] : lines.count)
        }
    }

    private func sectionRange(_ section: String) -> Range<Int>? {
        guard let start = lines.firstIndex(where: { Self.header($0) == section }) else { return nil }
        let end = lines.indices.dropFirst(start + 1).first { Self.header(lines[$0]) != nil || Self.header(Self.uncomment(lines[$0])) == "Rule" } ?? lines.count
        return start..<end
    }

    private func checkSyntax() throws {
        var section: String?; var sections = Set<String>(); var keys = Set<String>()
        for (offset, line) in lines.enumerated() {
            let clean = line.trimmingCharacters(in: .whitespaces)
            if clean.isEmpty || clean.hasPrefix("#") || clean.hasPrefix(";") { continue }
            if let header = Self.header(clean) {
                guard header == "Rule" || sections.insert(header).inserted else { throw ProfileError.duplicate(header) }
                section = header; keys.removeAll(); continue
            }
            guard section != nil else { throw ProfileError.syntax(offset + 1) }
            do {
                guard let pair = try Self.pair(clean), !pair.0.isEmpty else { throw ProfileError.syntax(offset + 1) }
                guard keys.insert(pair.0).inserted else { throw ProfileError.duplicate(pair.0) }
            } catch let error as ProfileError { throw error }
            catch { throw ProfileError.syntax(offset + 1) }
        }
    }

    private static func header(_ line: String) -> String? {
        let value = line.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("["), value.hasSuffix("]"), value.count > 2 else { return nil }
        return String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    private static func uncomment(_ line: String) -> String {
        let clean = line.trimmingCharacters(in: .whitespaces)
        guard clean.hasPrefix("#") else { return line }
        let rest = String(clean.dropFirst())
        return rest.hasPrefix(" ") ? String(rest.dropFirst()) : rest
    }

    private static func pair(_ line: String) throws -> (String, String)? {
        let clean = line.trimmingCharacters(in: .whitespaces)
        guard !clean.hasPrefix("#"), !clean.hasPrefix(";"), let equals = clean.firstIndex(of: "=") else { return nil }
        let key = String(clean[..<equals]).trimmingCharacters(in: .whitespaces)
        let value = String(clean[clean.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("\"") else { return (key, value) }
        // The documented config escapes are the JSON string escapes (excluding \/ and Unicode escapes).
        let decoded = try JSONDecoder().decode(String.self, from: Data(value.utf8))
        return (key, decoded)
    }

    private static func encode(_ value: String) -> String {
        if value.isEmpty || value != value.trimmingCharacters(in: .whitespaces) || value.contains("\"") || value.contains("\\") || value.contains(where: { $0.isNewline || $0 == "\t" }) {
            let escaped = value.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"").replacing("\n", with: "\\n").replacing("\r", with: "\\r").replacing("\t", with: "\\t")
            return "\"" + escaped + "\""
        }
        return value
    }
}
