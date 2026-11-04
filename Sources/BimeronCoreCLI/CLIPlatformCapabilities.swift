import Foundation

/// Static CLI build/platform declarations; these do not establish daemon readiness.
public struct CLIPlatformCapabilities: Decodable, Sendable {
    public struct IKEv2: Decodable, Sendable {
        public let administratorRequired: Bool
        public let supported: Bool
        public let foregroundOnly: Bool
        public let preconfiguredProfile: Bool
        public let proxy: Bool
        public let ipSplit: Bool
        public let domainSplit: Bool
        public let killSwitch: Bool
        public let dnsProtection: Bool
        public let stats: Bool
    }

    public let platform: String
    public let vpn: Bool
    public let proxy: Bool
    public let ipv4: Bool
    public let ipv6: Bool
    public let ipSplit: Bool
    public let domainSplit: Bool
    public let appSplit: Bool
    public let killSwitch: Bool
    public let daemon: Bool
    public let ikev2: IKEv2
}
