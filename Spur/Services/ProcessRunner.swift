import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "ProcessRunner")

// MARK: - Public types

struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ProcessOutput {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
}

enum ProcessRunnerError: Error, LocalizedError {
    case launchFailed(Error)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let error):
            return "Failed to launch process: \(error.localizedDescription)"
        }
    }
}

// MARK: - ProcessRunner

/// Safe, shell-free process runner.
///
/// CRITICAL: Every call uses `Process.executableURL` + `arguments` array.
/// Shell strings are never constructed. See plan.md §3.2 and agents.md §3.3.
final class ProcessRunner {

    // MARK: - run (collect all output)

    /// Runs a process to completion, capturing stdout and stderr.
    ///
    /// Stdout and stderr are drained concurrently on background threads to
    /// prevent pipe-buffer deadlocks with processes that produce large output.
    func run(
        executable: URL,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            // All blocking work runs on a background thread so we never block
            // Swift concurrency's cooperative thread pool.
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                if let wd = workingDirectory { process.currentDirectoryURL = wd }
                if let env = environment { process.environment = env }

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError  = stderrPipe

                do {
                    try process.run()
                    logger.debug("launched: \(executable.lastPathComponent) \(arguments.joined(separator: " "))")
                } catch {
                    logger.error("launch failed: \(error.localizedDescription)")
                    continuation.resume(throwing: ProcessRunnerError.launchFailed(error))
                    return
                }

                // Read stdout and stderr on separate threads to avoid deadlocking
                // when a process writes more than the pipe buffer (~64 KB) to either stream.
                var stdoutData = Data()
                var stderrData = Data()
                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                group.wait()
                process.waitUntilExit()

                let stdout = String(data: stdoutData, encoding: .utf8)?
                    .trimmingCharacters(in: .newlines) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .newlines) ?? ""

                logger.debug("exit \(process.terminationStatus): \(executable.lastPathComponent)")
                continuation.resume(returning: ProcessResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: process.terminationStatus
                ))
            }
        }
    }

    // MARK: - stream (line-by-line)

    /// Runs a process and streams stdout/stderr as `ProcessOutput` elements, one line at a time.
    ///
    /// The stream ends with a `.exit` element carrying the process exit code.
    /// Cancelling the `AsyncStream` sends `SIGTERM` to the process.
    func stream(
        executable: URL,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) -> AsyncStream<ProcessOutput> {
        AsyncStream { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let wd = workingDirectory { process.currentDirectoryURL = wd }
            if let env = environment { process.environment = env }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            let stdoutFH = stdoutPipe.fileHandleForReading
            let stderrFH = stderrPipe.fileHandleForReading

            // Per-stream line buffers for partial (no-newline) chunks
            var stdoutBuf = ""
            var stderrBuf = ""

            func emitLines(from buffer: inout String, as wrap: (String) -> ProcessOutput) {
                while let nlIdx = buffer.firstIndex(of: "\n") {
                    let line = String(buffer[..<nlIdx])
                    continuation.yield(wrap(line))
                    buffer = String(buffer[buffer.index(after: nlIdx)...])
                }
            }

            stdoutFH.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                stdoutBuf += text
                emitLines(from: &stdoutBuf, as: ProcessOutput.stdout)
            }

            stderrFH.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                stderrBuf += text
                emitLines(from: &stderrBuf, as: ProcessOutput.stderr)
            }

            process.terminationHandler = { proc in
                stdoutFH.readabilityHandler = nil
                stderrFH.readabilityHandler = nil

                // Drain any bytes the readability handler may have missed
                let remainingOut = stdoutFH.readDataToEndOfFile()
                if let text = String(data: remainingOut, encoding: .utf8), !text.isEmpty {
                    stdoutBuf += text
                }
                let remainingErr = stderrFH.readDataToEndOfFile()
                if let text = String(data: remainingErr, encoding: .utf8), !text.isEmpty {
                    stderrBuf += text
                }

                // Flush partial lines (no trailing newline)
                if !stdoutBuf.isEmpty { continuation.yield(.stdout(stdoutBuf)) }
                if !stderrBuf.isEmpty { continuation.yield(.stderr(stderrBuf)) }

                continuation.yield(.exit(proc.terminationStatus))
                continuation.finish()
            }

            // Allow the caller to cancel by terminating the process
            continuation.onTermination = { _ in process.terminate() }

            do {
                try process.run()
            } catch {
                logger.error("stream launch failed: \(error.localizedDescription)")
                continuation.yield(.exit(-1))
                continuation.finish()
            }
        }
    }
}
