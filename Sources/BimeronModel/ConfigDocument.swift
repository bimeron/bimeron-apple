import Foundation
import Darwin

/// Keeps source lines intact. Form edits replace only the field the user edited.
public struct ConfigDocument: Equatable, Sendable {
    public static let sizeLimit = 65_536
    private var lines: [String]
    private var bom: String
    private var newline: String
    private var shadowToggleOriginal: [String]?
    private var shadowToggleEnabled: Bool?

    public init(_ text: String) throws {
        guard text.utf8.count <= Self.sizeLimit else { throw ProfileError.tooLarge }
        let clean = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        bom = text.hasPrefix("\u{FEFF}") ? "\u{FEFF}" : ""
        newline = clean.first(where: { $0 == "\n" || $0 == "\r\n" }).map(String.init) ?? "\n"
        lines = []
        var start = clean.startIndex
        for index in clean.indices where clean[index] == "\n" || clean[index] == "\r\n" {
            let end = clean.index(after: index)
            lines.append(String(clean[start..<end]))
            start = end
        }
        if start < clean.endIndex { lines.append(String(clean[start...])) }
    }

    public init(data: Data) throws {
        guard data.count <= Self.sizeLimit else { throw ProfileError.tooLarge }
        guard String(data: data, encoding: .utf8) != nil else { throw ProfileError.invalidUTF8 }
        try self.init(String(decoding: data, as: UTF8.self))
    }

    public var text: String {
        bom + lines.enumerated().map { index, line in
            index < lines.count - 1 && !(line.hasSuffix("\n") || line.hasSuffix("\r\n")) ? line + newline : line
        }.joined()
    }

    private func replacement(_ value: String, for line: String) -> String {
        value + (line.hasSuffix("\r\n") ? "\r\n" : line.hasSuffix("\n") ? "\n" : "")
    }

    /// Loading never destroys invalid source; validation still blocks saving it.
    public var formEditingIssue: String? {
        do { try checkSyntax() } catch { return "Fix the raw config before switching to the form" }
        for range in ruleRanges {
            let enabled = Self.header(lines[range.lowerBound]) != nil
            let pairs = lines[range.dropFirst()].compactMap { try? Self.pair(enabled ? $0 : Self.uncomment($0)) }
            for line in lines[range.dropFirst()] {
                let clean = (enabled ? line : Self.uncomment(line)).trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.isEmpty || clean.hasPrefix("#") || clean.hasPrefix(";") { continue }
                if (try? Self.pair(clean)) == nil || !enabled && !line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") {
                    return "Unsupported routing rules require Raw editing"
                }
            }
            let keys = pairs.map(\.0)
            if keys.contains(where: { !["Domain", "CIDR", "Action"].contains($0) }) ||
                Set(keys).count != keys.count || keys.contains("Domain") && keys.contains("CIDR") {
                return "Unsupported routing rules require Raw editing"
            }
        }
        let shadows = blockRanges("ShadowTLS")
        if shadows.count > 1 { return "Ambiguous ShadowTLS blocks require Raw editing" }
        if let range = shadows.first {
            let disabled = Self.header(lines[range.lowerBound]) == nil
            var keys = Set<String>()
            for line in lines[range.dropFirst()] {
                let clean = disabled ? Self.uncomment(line) : line
                let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") { continue }
                guard let pair = try? Self.pair(clean), ["ServerName", "Password"].contains(pair.0),
                      keys.insert(pair.0).inserted else {
                    return "Ambiguous ShadowTLS fields require Raw editing"
                }
                if disabled {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                        return "Ambiguous ShadowTLS boundary requires Raw editing"
                    }
                }
            }
        }
        return nil
    }

    /// Early form feedback for known incompatible options, without rewriting inactive fields.
    public var editorCompatibilityIssue: String? {
        guard isExplicit else { return nil }
        func field(_ key: String) -> String { value("AccessKey", key) ?? "" }
        if accessProtocol == .shadowsocks, field("Method").hasPrefix("2022-"), !field("Prefix").isEmpty {
            return "SS2022 does not support Prefix. Clear Prefix before saving."
        }
        if accessProtocol == .vless {
            let network = field("Network").isEmpty ? "tcp" : field("Network")
            let security = field("Security")
            let realityFields = ["PublicKey", "ShortID", "SpiderX"].contains { !field($0).isEmpty }
            if !["tls", "reality"].contains(security) ||
                !field("Flow").isEmpty && !(network == "tcp" && security == "reality") ||
                security != "reality" && realityFields ||
                network == "ws" && security != "tls" ||
                network != "grpc" && (["GRPCServiceName", "GRPCAuthority"].contains(where: { !field($0).isEmpty }) || field("GRPCMultiMode") == "true") ||
                network != "ws" && !field("WSEarlyData").isEmpty && field("WSEarlyData") != "0" ||
                network != "ws" && network != "xhttp" && ["WSPath", "WSHost"].contains(where: { !field($0).isEmpty }) ||
                network != "xhttp" && ["XHTTPMode", "XHTTPPath", "XHTTPHost", "XHTTPExtra"].contains(where: { !field($0).isEmpty }) {
                return "Incompatible transport, security or flow. Correct the settings; all draft values are retained."
            }
        }
        return nil
    }

    /// Conservative form gate. Core remains authoritative for opaque URI details.
    public var shadowTLSCompatibilityIssue: String? {
        guard let accessProtocol,
              [.shadowsocks, .dynamicShadowsocks, .vless, .vmess, .trojan, .anytls, .naive, .ssh].contains(accessProtocol) else {
            return "ShadowTLS requires a compatible encrypted TCP upstream"
        }
        if !isExplicit, let uri = URLComponents(string: accessKey) {
            let query = uri.queryItems ?? []
            if query.contains(where: { $0.name == "plugin" && !($0.value ?? "").isEmpty || $0.name == "alpn" && ($0.value ?? "").contains("h3") }) ||
                accessProtocol == .vless && !query.contains(where: { $0.name == "security" && ["tls", "reality"].contains($0.value ?? "") }) ||
                accessProtocol == .shadowsocks && uri.user == "aes-192-gcm" {
                return "ShadowTLS requires a compatible encrypted TCP upstream"
            }
        }
        if accessKey.lowercased().hasPrefix("naive+quic://") ||
            !(value("AccessKey", "Plugin") ?? "").isEmpty || value("AccessKey", "Method") == "aes-192-gcm" ||
            isExplicit && accessProtocol == .vless && !["tls", "reality"].contains(value("AccessKey", "Security") ?? "") ||
            (value("AccessKey", "ALPN") ?? "").contains("h3") {
            return "ShadowTLS requires a compatible encrypted TCP upstream"
        }
        return nil
    }

    /// Inspection never feeds back into serialization of the original access key.
    public var vlessInspection: [(String, String)] {
        guard accessProtocol == .vless, !isExplicit, let components = URLComponents(string: accessKey) else { return [] }
        var result: [(String, String)] = []
        if let host = components.host { result.append(("Server", host)) }
        if let port = components.port { result.append(("Port", String(port))) }
        if let user = components.user { result.append(("User ID", user)) }
        for item in components.queryItems ?? [] { result.append((item.name, item.value ?? "")) }
        return result
    }

    public var shadowTLSEnabled: Bool { hasSection("ShadowTLS") }
    public var hasShadowTLSDraft: Bool { !blockRanges("ShadowTLS").isEmpty }

    public func shadowTLSValue(_ key: String) -> String? {
        guard let range = blockRanges("ShadowTLS").first else { return nil }
        let enabled = Self.header(lines[range.lowerBound]) != nil
        return lines[range.dropFirst()].compactMap { try? Self.pair(enabled ? $0 : Self.uncomment($0)) }
            .first { $0.0 == key }?.1
    }

    public mutating func setShadowTLSValue(_ key: String, _ value: String) {
        guard formEditingIssue == nil, (shadowTLSValue(key) ?? "") != value else { return }
        let enabled = shadowTLSEnabled
        if hasShadowTLSDraft && !enabled { setShadowTLSEnabled(true) }
        shadowToggleOriginal = nil
        shadowToggleEnabled = nil
        if value.isEmpty { remove("ShadowTLS", key) } else { set("ShadowTLS", key, value) }
        if !enabled { setShadowTLSEnabled(false) }
        shadowToggleOriginal = nil
        shadowToggleEnabled = nil
    }

    public mutating func setShadowTLSEnabled(_ enabled: Bool) {
        guard formEditingIssue == nil else { return }
        if enabled == shadowToggleEnabled, let original = shadowToggleOriginal {
            if let range = blockRanges("ShadowTLS").first { lines.replaceSubrange(range, with: original) }
            shadowToggleOriginal = nil
            shadowToggleEnabled = nil
            return
        }
        guard let range = blockRanges("ShadowTLS").first else {
            if enabled { lines.append("[ShadowTLS]" + newline) }
            return
        }
        guard enabled != shadowTLSEnabled else { return }
        if !enabled && ["ServerName", "Password"].allSatisfy({ (shadowTLSValue($0) ?? "").isEmpty }) {
            // Removing an empty draft must not remove the user's surrounding comments.
            let comments = lines[range.dropFirst()].filter { (try? Self.pair($0)) == nil }
            lines.replaceSubrange(range, with: comments)
            return
        }
        shadowToggleOriginal = Array(lines[range])
        shadowToggleEnabled = shadowTLSEnabled
        let block = lines[range].filter {
            enabled || (try? Self.pair($0))?.1 != ""
        }.map { enabled ? Self.uncomment($0) : "# " + $0 }
        lines.replaceSubrange(range, with: block)
    }

    private func blockRanges(_ section: String) -> [Range<Int>] {
        let starts = lines.indices.filter { Self.header(lines[$0]) != nil || ["Rule", "ShadowTLS"].contains(Self.header(Self.uncomment(lines[$0])) ?? "") }
        return starts.enumerated().compactMap { offset, start in
            guard Self.header(lines[start]) == section || Self.header(Self.uncomment(lines[start])) == section else { return nil }
            return start..<(offset + 1 < starts.count ? starts[offset + 1] : lines.count)
        }
    }

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
        guard self.value(section, key) != value else { return }
        let replacement = "\(key) = \(Self.encode(value))"
        if let range = sectionRange(section) {
            if let index = range.first(where: { (try? Self.pair(lines[$0]))?.0 == key }) {
                lines[index] = self.replacement(replacement, for: lines[index])
            } else {
                lines.insert(replacement + newline, at: range.lowerBound + 1)
            }
        } else {
            lines.append(contentsOf: [newline, "[\(section)]" + newline, replacement + newline])
        }
    }

    /// Only a matching URI source has clear ownership; never remove a Raw schema or its extensions.
    public mutating func restoreGeneratedSource(_ source: String, value: String) throws {
        try checkSyntax()
        guard Self.sourceKeys.filter({ self.value("AccessKey", $0) != nil }) == [source],
              self.value("AccessKey", "Type") == nil, self.value("AccessKey", "Server") == nil,
              let range = sectionRange("AccessKey"),
              let index = range.first(where: { (try? Self.pair(lines[$0]))?.0 == source }) else {
            throw ProfileError.invalid("GeneratedAccessKey")
        }
        guard accessKey != value else { return }
        let line = lines[index]
        let equals = line.firstIndex(of: "=")!
        let suffix = line[line.index(after: equals)...]
        let start = suffix.firstIndex(where: { !$0.isWhitespace }) ?? suffix.startIndex
        let end = suffix.lastIndex(where: { !$0.isWhitespace }).map { line.index(after: $0) } ?? start
        lines[index].replaceSubrange(start..<end, with: Self.encode(value))
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
        guard self.mode != mode else { return }
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
        lines[index] = replacement("Key = \(Self.encode(key))", for: lines[index])
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
        try Self.validateName(name)
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
            guard shadowTLSCompatibilityIssue == nil else { throw ProfileError.invalid("ShadowTLS") }
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

    public static func validateName(_ name: String) throws {
        guard name.count <= 128, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw ProfileError.invalid("Name") }
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
        let original = rules[rule.id]
        guard original != rule else { return }
        let range = ruleRanges[rule.id]
        let wasEnabled = Self.header(lines[range.lowerBound]) == "Rule"
        var block = Array(lines[range]).map { wasEnabled ? $0 : Self.uncomment($0) }
        for (key, value) in [(rule.type, rule.destination), ("Action", rule.action)] {
            if key == "Action" && original.action == value { continue }
            if key != "Action" && original.type == key && original.destination == value { continue }
            let candidates = key == "Action" ? ["Action"] : ["CIDR", "Domain"]
            if let index = block.indices.first(where: { candidates.contains((try? Self.pair(block[$0]))?.0 ?? "") }) {
                if (try? Self.pair(block[index]))?.0 != key || (try? Self.pair(block[index]))?.1 != value {
                    block[index] = replacement("\(key) = \(Self.encode(value))", for: block[index])
                }
            } else { block.append("\(key) = \(Self.encode(value))" + newline) }
        }
        if !rule.enabled {
            block = block.enumerated().map { offset, line in
                if !wasEnabled, offset < range.count,
                   line == Self.uncomment(lines[range.lowerBound + offset]) {
                    return lines[range.lowerBound + offset]
                }
                return line.isEmpty ? line : "# " + line
            }
        }
        lines.replaceSubrange(range, with: block)
    }

    public mutating func addRule() {
        lines.append(contentsOf: [newline, "[Rule]" + newline, "Domain = example.com" + newline, "Action = proxy" + newline])
    }

    public mutating func removeRule(_ index: Int) {
        guard ruleRanges.indices.contains(index) else { return }
        lines.removeSubrange(ruleRanges[index])
    }

    public mutating func moveRule(_ index: Int, by offset: Int) {
        let ranges = ruleRanges
        guard offset == -1 || offset == 1, ranges.indices.contains(index) else { return }
        let destination = index.addingReportingOverflow(offset)
        guard !destination.overflow, ranges.indices.contains(destination.partialValue) else { return }
        let other = destination.partialValue
        let low = min(index, other), high = max(index, other)
        let lowBlock = Array(lines[ranges[low]]), highBlock = Array(lines[ranges[high]])
        lines.replaceSubrange(ranges[high], with: lowBlock)
        lines.replaceSubrange(ranges[low], with: highBlock)
    }

    private var ruleRanges: [Range<Int>] { blockRanges("Rule") }

    private func sectionRange(_ section: String) -> Range<Int>? {
        guard let start = lines.firstIndex(where: { Self.header($0) == section }) else { return nil }
        let end = lines.indices.dropFirst(start + 1).first { Self.header(lines[$0]) != nil || ["Rule", "ShadowTLS"].contains(Self.header(Self.uncomment(lines[$0])) ?? "") } ?? lines.count
        return start..<end
    }

    private func checkSyntax() throws {
        var section: String?; var sections = Set<String>(); var keys = Set<String>()
        for (offset, line) in lines.enumerated() {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("["), value.hasSuffix("]"), value.count > 2 else { return nil }
        return String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    private static func uncomment(_ line: String) -> String {
        let clean = line.drop(while: { $0 == " " || $0 == "\t" })
        guard clean.hasPrefix("#") else { return line }
        let rest = String(clean.dropFirst())
        return rest.hasPrefix(" ") ? String(rest.dropFirst()) : rest
    }

    private static func pair(_ line: String) throws -> (String, String)? {
        let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.hasPrefix("#"), !clean.hasPrefix(";"), let equals = clean.firstIndex(of: "=") else { return nil }
        let key = String(clean[..<equals]).trimmingCharacters(in: .whitespaces)
        let value = String(clean[clean.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("\"") else {
            guard !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw ProfileError.invalid("Value")
            }
            return (key, value)
        }
        // Core only accepts these escapes; JSON's Unicode and slash escapes are unsafe here.
        var escaping = false
        for character in value.dropFirst().dropLast() {
            if escaping {
                guard ["\\", "\"", "n", "r", "t"].contains(character) else { throw ProfileError.invalid("Quoted value") }
                escaping = false
            } else if character == "\\" { escaping = true }
        }
        let decoded = try JSONDecoder().decode(String.self, from: Data(value.utf8))
        return (key, decoded)
    }

    private static func encode(_ value: String) -> String {
        if value.isEmpty || value != value.trimmingCharacters(in: .whitespaces) || value.hasPrefix("\"") || value.contains(where: { $0.isNewline || $0 == "\t" }) {
            let escaped = value.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"").replacing("\n", with: "\\n").replacing("\r", with: "\\r").replacing("\t", with: "\\t")
            return "\"" + escaped + "\""
        }
        return value
    }
}
