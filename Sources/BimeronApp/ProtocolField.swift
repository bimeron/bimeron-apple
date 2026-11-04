import BimeronModel

struct ProtocolField: Identifiable {
    let id: String
    let title: String
    var secret = false
    var file = false

    init(_ key: String, title: String? = nil, secret: Bool = false, file: Bool = false) {
        id = key
        self.title = title ?? key
        self.secret = secret
        self.file = file
    }

    static func fields(for protocolType: AccessProtocol) -> [Self] {
        let endpoint = [Self("Server"), Self("Port")]
        let credentials = [Self("Username"), Self("Password", secret: true)]
        let sni = Self("ServerName", title: "Server name (SNI)")
        switch protocolType {
        case .shadowsocks:
            return endpoint + [Self("Method", title: "Encryption"), Self("Password", secret: true),
                               Self("Prefix"), Self("Plugin"), Self("PluginOpts", title: "Plugin options")]
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
            return endpoint + [Self("ID", title: "User ID"), Self("Encryption"), Self("Flow"), sni,
                               Self("PublicKey", title: "REALITY public key"), Self("ShortID", title: "REALITY short ID"),
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
