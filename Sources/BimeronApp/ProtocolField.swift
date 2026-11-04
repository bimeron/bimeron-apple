import BimeronModel

struct ProtocolField: Identifiable {
    let id: String
    let title: String
    var secret = false
    var file = false
    var choices: [String]? {
        switch id {
        case "Method": ["aes-128-gcm", "aes-192-gcm", "aes-256-gcm", "chacha20-ietf-poly1305", "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305"]
        case "Plugin": ["", "obfs-local", "v2ray-plugin"]
        case "VMessSecurity": ["auto", "none", "aes-128-gcm", "chacha20-poly1305", "zero"]
        case "VMessNetwork": ["tcp", "ws", "grpc", "xhttp"]
        case "VMessTLS": ["tls", "", "reality"]
        case "Network": ["", "tcp", "ws", "grpc", "xhttp"]
        case "Security": ["", "tls", "reality"]
        case "Flow": ["", "xtls-rprx-vision", "xtls-rprx-vision-udp443"]
        case "Encryption": ["", "none"]
        case "Fingerprint": ["", "chrome", "firefox", "safari", "ios", "android", "edge"]
        case "XHTTPMode": ["", "auto", "packet-up", "stream-up", "stream-one"]
        case "GRPCMultiMode": ["", "false", "true"]
        default: nil
        }
    }

    init(_ key: String, title: String? = nil, secret: Bool = false, file: Bool = false) {
        id = key
        self.title = title ?? key
        self.secret = secret
        self.file = file
    }

    static func generated(_ key: String) -> Self {
        let titles = ["ID": "User ID", "ServerName": "Server name (SNI)", "Fingerprint": "Client fingerprint",
                      "PublicKey": "REALITY public key", "ShortID": "REALITY short ID", "SpiderX": "REALITY spider path",
                      "VMessSecurity": "Encryption", "VMessNetwork": "Transport", "VMessTLS": "Security",
                      "VMessPath": "Transport path", "VMessHost": "Transport host", "VMessMode": "Transport mode",
                      "VMessExtra": "Transport extra options"]
        return Self(key, title: titles[key], secret: ["Password", "ID", "PublicKey", "ShortID"].contains(key))
    }

    static func fields(for protocolType: AccessProtocol) -> [Self] {
        let endpoint = [Self("Server"), Self("Port")]
        let credentials = [Self("Username"), Self("Password", secret: true)]
        let sni = Self("ServerName", title: "Server name (SNI)")
        switch protocolType {
        case .shadowsocks:
            return endpoint + [Self("Method", title: "Encryption"), Self("Password", secret: true),
                               Self("Prefix"), Self("Plugin"), Self("PluginOpts", title: "Plugin options", secret: true)]
        case .socks5:
            return endpoint + credentials
        case .http:
            return endpoint + credentials
        case .masque:
            return endpoint + credentials + [sni, Self("MASQUEPath", title: "CONNECT-UDP path"),
                                             Self("CAFile", title: "CA certificate file", file: true)]
        case .ssh:
            return endpoint + [Self("Username")]
        case .naive:
            return endpoint + credentials + [sni]
        case .trojan:
            return endpoint + [Self("Password", secret: true), sni] + transportFields
        case .vless:
            return endpoint + [Self("ID", title: "User ID", secret: true), Self("Encryption"), Self("Flow"), sni,
                               Self("PublicKey", title: "REALITY public key", secret: true), Self("ShortID", title: "REALITY short ID", secret: true),
                               Self("SpiderX"), Self("Fingerprint", title: "Client fingerprint")]
                + transportFields + [Self("WSEarlyData", title: "WebSocket early data"),
                                     Self("XHTTPMode", title: "XHTTP mode"), Self("XHTTPPath", title: "XHTTP path"),
                                     Self("XHTTPHost", title: "XHTTP host"), Self("XHTTPExtra", title: "XHTTP extra")]
        case .dynamicShadowsocks, .vmess, .hysteria2, .anytls, .tuic:
            return []
        }
    }

    private static var transportFields: [Self] {
        [Self("Network", title: "Transport"), Self("Security"), Self("ALPN"),
         Self("WSPath", title: "WebSocket path"), Self("WSHost", title: "WebSocket host"),
         Self("GRPCServiceName", title: "gRPC service"), Self("GRPCAuthority", title: "gRPC host"),
         Self("GRPCMultiMode", title: "gRPC multi mode")]
    }
}
