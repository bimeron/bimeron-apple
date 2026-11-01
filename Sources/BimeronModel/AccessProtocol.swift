import Foundation

/// Access sources and URI aliases in core profile format 1.
public enum AccessProtocol: String, CaseIterable, Sendable {
    case shadowsocks = "SS", dynamicShadowsocks = "SSConf", socks5 = "SOCKS5"
    case http = "HTTP", masque = "MASQUE", vless = "VLESS", vmess = "VMess"
    case trojan = "Trojan", naive = "Naive", hysteria2 = "Hysteria2"
    case anytls = "AnyTLS", ssh = "SSH", tuic = "TUIC"

    public var schemes: [String] {
        switch self {
        case .shadowsocks: ["ss"]
        case .dynamicShadowsocks: ["ssconf"]
        case .socks5: ["socks5"]
        case .http: ["http", "https"]
        case .masque: ["masque"]
        case .vless: ["vless"]
        case .vmess: ["vmess"]
        case .trojan: ["trojan"]
        case .naive: ["naive+https", "naive+quic"]
        case .hysteria2: ["hysteria2", "hy2"]
        case .anytls: ["anytls"]
        case .ssh: ["ssh"]
        case .tuic: ["tuic"]
        }
    }

    public var title: String {
        switch self {
        case .shadowsocks: "Shadowsocks"
        case .dynamicShadowsocks: "Shadowsocks ⟳"
        case .http: "HTTP CONNECT"
        case .naive: "NaiveProxy"
        case .tuic: "TUIC v5"
        default: rawValue
        }
    }

    public init?(key: String) {
        guard let separator = key.range(of: "://") else { return nil }
        let scheme = key[..<separator.lowerBound].lowercased()
        guard let value = Self.allCases.first(where: { $0.schemes.contains(scheme) }) else { return nil }
        self = value
    }

    public init?(explicitType: String) {
        switch explicitType {
        case "ss", "shadowsocks": self = .shadowsocks
        case "socks5": self = .socks5
        case "http", "https": self = .http
        case "masque": self = .masque
        case "vless": self = .vless
        case "trojan": self = .trojan
        case "naive": self = .naive
        case "ssh": self = .ssh
        default: return nil
        }
    }
}
