import Foundation

public struct CLIOutput: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool

    public var diagnosticText: String { String(decoding: stderr, as: UTF8.self) }
}
