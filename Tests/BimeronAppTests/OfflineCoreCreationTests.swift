import Foundation
import Testing
import BimeronCoreCLI
import BimeronModel

/// Opt-in local parser validation only; never inspects, connects, or starts Core runtime.
@Test(.enabled(if: ProcessInfo.processInfo.environment["BIMERON_CORE_EXECUTABLE"] != nil,
               "Set BIMERON_CORE_EXECUTABLE to an absolute offline Core CLI path"),
      arguments: EditorProtocol.allCases)
func offlineCoreAcceptsCreationVariant(_ variant: EditorProtocol) async throws {
    let path = try #require(ProcessInfo.processInfo.environment["BIMERON_CORE_EXECUTABLE"])
    #expect(path.hasPrefix("/"))
    guard path.hasPrefix("/") else { return }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let values = ["Server": "server.example.com", "Port": "443", "Password": "synthetic:@/?# %pass",
                  "Username": "test-user", "ID": "123e4567-e89b-12d3-a456-426614174000",
                  "Method": "aes-256-gcm", "Security": "tls", "Encryption": "none", "Network": "tcp",
                  "ServerName": "server.example.com"]
    let keys: [String]
    switch variant {
    case .ss: keys = ["Server", "Port", "Password", "Method"]
    case .vless: keys = ["Server", "Port", "ID", "Security", "Encryption", "Network", "ServerName"]
    case .ssh: keys = ["Server", "Port", "Username"]
    case .trojan: keys = ["Server", "Port", "Password", "Security", "Network", "ServerName"]
    case .socks5, .http, .https: keys = ["Server", "Port", "Username", "Password"]
    case .naiveH2, .masque: keys = ["Server", "Port", "Username", "Password", "ServerName"]
    default: keys = variant.fields
    }
    let document = try variant.document(name: "Synthetic " + variant.rawValue,
                                        values: values.filter { keys.contains($0.key) })
    try document.validateLocally()
    let file = root.appending(path: "synthetic.conf")
    try Data(document.text.utf8).write(to: file)
    _ = try await CoreCLI(executableURL: URL(fileURLWithPath: path)).validate(fileURL: file)
}
