import Foundation

public struct CLIBuildInfo: Decodable, Sendable {
    public let version: String
    public let revision: String?
    public let commitTime: String?
    public let modified: Bool
    public let goVersion: String
    public let platform: String
    public let architecture: String
}
