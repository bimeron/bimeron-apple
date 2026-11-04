import Foundation

public enum CoreCLIError: Error, Sendable, LocalizedError {
    case launch(executable: URL, message: String)
    case exit(status: Int32, output: CLIOutput)
    case decode(command: String, message: String, output: CLIOutput)
    case timedOut(output: CLIOutput)
    case cancelled(output: CLIOutput)
    case read(message: String, output: CLIOutput)

    public var errorDescription: String? {
        switch self {
        case let .launch(url, message): "Cannot launch Core at \(url.path): \(message)"
        case let .exit(status, output): "Core exited with status \(status): \(output.diagnosticText)"
        case let .decode(command, message, output): "Invalid Core \(command) JSON: \(message). \(output.diagnosticText)"
        case let .timedOut(output): "Core command timed out. \(output.diagnosticText)"
        case let .cancelled(output): "Core command cancelled. \(output.diagnosticText)"
        case let .read(message, output): "Cannot read Core output: \(message). \(output.diagnosticText)"
        }
    }
}
