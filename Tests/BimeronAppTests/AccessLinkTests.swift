import Testing
@testable import BimeronApp

@Test @MainActor func addDialogAcceptsCurrentCoreSchemesIncludingTrojan() {
    for link in ["trojan://password@example.com:443", "vmess://encoded", "https://example.com:443",
                 "masque://example.com:443", "naive+quic://user:password@example.com:443",
                 "hysteria2://password@example.com:443", "hy2://password@example.com:443",
                 "anytls://password@example.com:443", "ssh://user@example.com:22", "tuic://example.com:443"] {
        #expect(AddProfileView.accepts("\n " + link + " \n"))
    }
    #expect(!AddProfileView.accepts("https://"))
    #expect(!AddProfileView.accepts("wireguard://example.com"))
}
