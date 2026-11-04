import Foundation
import Darwin

public struct CoreCLI: Sendable {
    public let executableURL: URL
    public let timeout: Duration
    public let outputLimit: Int

    public init(executableURL: URL, timeout: Duration = .seconds(10), outputLimit: Int = 1_048_576) {
        precondition(timeout > .zero && outputLimit > 0)
        self.executableURL = executableURL
        self.timeout = timeout
        self.outputLimit = outputLimit
    }

    public func version() async throws -> CLIBuildInfo {
        try await decode("version")
    }

    public func capabilities() async throws -> CLIPlatformCapabilities {
        try await decode("capabilities")
    }

    /// Reads the caller's existing file in place, preserving its relative references.
    public func validate(fileURL: URL) async throws -> CLIOutput {
        try await run(["validate", fileURL.path])
    }

    private func decode<T: Decodable>(_ command: String) async throws -> T {
        let output = try await run([command])
        do {
            guard !output.stdoutTruncated else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Output exceeded capture limit"))
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: output.stdout)
        } catch {
            throw CoreCLIError.decode(command: command, message: String(describing: error), output: output)
        }
    }

    private func run(_ arguments: [String]) async throws -> CLIOutput {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        defer {
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
        }
        var out = CapturedStream(fd: stdout.fileHandleForReading.fileDescriptor, limit: outputLimit)
        var err = CapturedStream(fd: stderr.fileHandleForReading.fileDescriptor, limit: outputLimit)
        let clock = ContinuousClock()
        var stoppedAt: ContinuousClock.Instant?
        var exitedAt: ContinuousClock.Instant?
        var cancelled = false
        var timedOut = false
        var readFailure: String?
        do {
            try out.makeNonblocking()
            try err.makeNonblocking()
            if Task.isCancelled { throw CancellationError() }
            try process.run()
        } catch is CancellationError {
            throw CoreCLIError.cancelled(output: Self.output(out, err))
        } catch {
            throw CoreCLIError.launch(executable: executableURL, message: error.localizedDescription)
        }
        let deadline = clock.now.advanced(by: timeout)
        // Close parent writers so EOF is observable after the child closes its descriptors.
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        while true {
            do {
                try out.drain()
                try err.drain()
            } catch { readFailure = error.localizedDescription }
            let now = clock.now
            let running = process.isRunning
            if stoppedAt == nil && (Task.isCancelled || now >= deadline || readFailure != nil) {
                cancelled = Task.isCancelled
                timedOut = !cancelled && now >= deadline
                stoppedAt = now
                if running { process.terminate() }
            }
            if let stoppedAt, now >= stoppedAt.advanced(by: .milliseconds(200)), running {
                // Process owns this PID until termination is observed; never signal a reaped PID.
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
            if !running {
                if exitedAt == nil { exitedAt = now }
                if out.eof && err.eof { break }
                // Descendants may inherit pipes; never wait indefinitely for their EOF.
                if let exitedAt, now >= exitedAt.advanced(by: .milliseconds(200)) { break }
            }
            if let stoppedAt, now >= stoppedAt.advanced(by: .seconds(1)) { break }
            // Cancellation is recorded above; a cancelled sleep must not become a busy loop.
            await Task.detached { try? await Task.sleep(for: .milliseconds(5)) }.value
        }
        let output = Self.output(out, err)
        if cancelled { throw CoreCLIError.cancelled(output: output) }
        if timedOut { throw CoreCLIError.timedOut(output: output) }
        if let readFailure { throw CoreCLIError.read(message: readFailure, output: output) }
        guard process.terminationStatus == 0 else {
            throw CoreCLIError.exit(status: process.terminationStatus, output: output)
        }
        return output
    }

    private static func output(_ out: CapturedStream, _ err: CapturedStream) -> CLIOutput {
        CLIOutput(stdout: out.data, stderr: err.data, stdoutTruncated: out.truncated, stderrTruncated: err.truncated)
    }
}

