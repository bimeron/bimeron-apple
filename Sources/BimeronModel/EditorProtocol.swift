import Foundation

/// Creation variants match Desktop 296130e; imported links never pass through this encoder.
public enum EditorProtocol: String, CaseIterable, Sendable {
    case ss = "SS", socks5 = "SOCKS5", vless = "VLESS", ssh = "SSH", trojan = "Trojan"
    case http = "HTTP", https = "HTTPS", naiveH2 = "Naive H2", masque = "MASQUE"
    case hysteria2 = "Hysteria2", vmess = "VMess", tuic = "TUIC", anytls = "AnyTLS", naiveQUIC = "Naive QUIC"

    public var defaultPort: String {
        switch self {
        case .ss: "8388"
        case .socks5: "1080"
        case .ssh: "22"
        case .http: "8080"
        default: "443"
        }
    }

    public var generated: Bool { [.hysteria2, .vmess, .tuic, .anytls, .naiveQUIC].contains(self) }
    public var type: String {
        switch self {
        case .ss: "shadowsocks"
        case .naiveH2, .naiveQUIC: "naive"
        default: rawValue.lowercased()
        }
    }
    public var fields: [String] {
        let endpoint = ["Server", "Port"]
        switch self {
        case .hysteria2: return endpoint + ["Password", "ServerName", "ALPN", "Fingerprint"]
        case .tuic: return endpoint + ["ID", "Password", "ServerName", "ALPN"]
        case .anytls: return endpoint + ["Password", "ServerName"]
        case .naiveQUIC: return endpoint + ["Username", "Password", "ServerName"]
        case .vmess: return endpoint + ["ID", "VMessSecurity", "VMessNetwork", "VMessTLS", "VMessPath", "VMessHost", "VMessMode", "VMessExtra", "ServerName", "ALPN", "Fingerprint", "PublicKey", "ShortID", "SpiderX"]
        default: return endpoint
        }
    }

    public func document(name: String, values: [String: String]) throws -> ConfigDocument {
        try ConfigDocument.validateName(name)
        func field(_ key: String) -> String { values[key] ?? "" }
        // ConfigDocument.set is line-oriented; reject line injection before serialization.
        guard !values.values.contains(where: { $0.contains(where: { $0.isNewline || $0 == "\0" }) }) else {
            throw ProfileError.invalid("AccessKey")
        }
        var document = try ConfigDocument("[Profile]\nVersion = 1\n[AccessKey]\n[Interface]\nMode = vpn\n[Routing]\nDefault = proxy\n")
        document.set("Profile", "Name", name)
        if generated {
            let link: String
            do { link = try uri(values: values) }
            catch ProfileError.invalid("Server or Port") { link = "" } // Incomplete drafts remain editable; the UI explains the missing endpoint.
            if !link.isEmpty { try ConfigDocument.validateKey(link) }
            document.set("AccessKey", self == .naiveQUIC ? "Naive" : rawValue, link)
        } else {
            document.set("AccessKey", "Type", type)
            for (key, value) in values where !value.isEmpty { document.set("AccessKey", key, value) }
            if field("Port").isEmpty { document.set("AccessKey", "Port", defaultPort) }
        }
        return document
    }

    public func uri(values: [String: String]) throws -> String {
        guard !values.values.contains(where: { $0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else {
            throw ProfileError.invalid("AccessKey")
        }
        func field(_ key: String) -> String {
            values[key] ?? (self == .vmess ? ["VMessSecurity": "auto", "VMessNetwork": "tcp", "VMessTLS": "tls"][key] : nil) ?? ""
        }
        let port = field("Port").isEmpty ? defaultPort : field("Port")
        guard let number = Int(port), (1...65535).contains(number), !field("Server").isEmpty else {
            throw ProfileError.invalid("Server or Port")
        }
        if self == .vmess {
            var object = ["v": "2", "add": field("Server"), "port": port, "id": field("ID"), "aid": "0"]
            for (key, source) in ["scy": "VMessSecurity", "net": "VMessNetwork", "tls": "VMessTLS", "path": "VMessPath", "host": "VMessHost", "mode": "VMessMode", "extra": "VMessExtra", "sni": "ServerName", "alpn": "ALPN", "fp": "Fingerprint", "pbk": "PublicKey", "sid": "ShortID", "spx": "SpiderX"] where !field(source).isEmpty {
                object[key] = field(source)
            }
            return "vmess://" + (try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])).base64EncodedString()
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: allowed)! }
        var host = field("Server")
        if host.contains(":"), !host.hasPrefix("[") { host = "[" + host + "]" }
        var user = encode(field("Password"))
        if self == .tuic { user = encode(field("ID")) + ":" + user }
        if self == .naiveQUIC { user = encode(field("Username")) + ":" + user }
        let query = [("sni", "ServerName"), ("alpn", "ALPN"), ("fp", "Fingerprint")]
            .filter { fields.contains($0.1) && !field($0.1).isEmpty }
            .map { $0.0 + "=" + encode(field($0.1)) }.joined(separator: "&")
        return (self == .naiveQUIC ? "naive+quic" : type) + "://" + user + "@" + host + ":" + port + (query.isEmpty ? "" : "?" + query)
    }
}
