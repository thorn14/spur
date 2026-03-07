import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "DevServerService")

// MARK: - Error types

enum DevServerError: Error, LocalizedError {
    case alreadyRunning(UUID)
    case startFailed(String)
    case notRunning(UUID)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning(let id): return "Dev server for option \(id) is already running."
        case .startFailed(let reason): return "Dev server failed to start: \(reason)"
        case .notRunning(let id):      return "No dev server running for option \(id)."
        }
    }
}

// MARK: - DevServerService

final class DevServerService {

    // MARK: - Private types

    private struct RunningServer {
        let process: Process
        let continuation: AsyncStream<String>.Continuation
    }

    // MARK: - State

    /// Protected by `serversLock`. Accessed from main thread (OptionViewModel) and
    /// background threads (Process terminationHandler, readabilityHandlers).
    private var servers: [UUID: RunningServer] = [:]
    private let serversLock = NSLock()

    deinit {
        stopAll()
    }

    // MARK: - Public API

    /// Starts a dev server for `optionId`. Returns an `AsyncStream` of log lines.
    /// Throws `DevServerError.alreadyRunning` synchronously by returning a finished stream
    /// (callers should check `isRunning` before calling).
    func start(
        optionId: UUID,
        worktreePath: String,
        port: Int,
        command: String = Constants.defaultDevCommand
    ) -> AsyncStream<String> {
        serversLock.lock()
        let alreadyRunning = servers[optionId] != nil
        serversLock.unlock()

        guard !alreadyRunning else {
            return AsyncStream { continuation in
                continuation.yield("[spur] Error: server already running for this option.")
                continuation.finish()
            }
        }

        let parts = parseCommand(command)
        guard !parts.isEmpty else {
            return AsyncStream { continuation in
                continuation.yield("[spur] Error: empty command — cannot start dev server.")
                continuation.finish()
            }
        }

        let worktreeURL = URL(fileURLWithPath: worktreePath)

        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = parts
            process.currentDirectoryURL = worktreeURL

            // Inject PORT; inherit rest of environment
            var env = ProcessInfo.processInfo.environment
            env["PORT"] = "\(port)"
            env["FORCE_COLOR"] = "0"
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            // Serial I/O queue for this process — prevents data races on the buffers
            let ioQueue = DispatchQueue(label: "com.spur.devserver.io.\(optionId)")
            var stdoutBuffer = ""
            var stderrBuffer = ""

            func flushBuffer(_ buffer: inout String, prefix: String) {
                let lines = buffer.components(separatedBy: "\n")
                for line in lines.dropLast() {
                    let trimmed = line.trimmingCharacters(in: .controlCharacters)
                    if !trimmed.isEmpty { continuation.yield(prefix + trimmed) }
                }
                buffer = lines.last ?? ""
            }

            func ingest(_ data: Data, into buffer: inout String, prefix: String) {
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                buffer += str
                flushBuffer(&buffer, prefix: prefix)
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                ioQueue.async { ingest(data, into: &stdoutBuffer, prefix: "") }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                ioQueue.async { ingest(data, into: &stderrBuffer, prefix: "[stderr] ") }
            }

            process.terminationHandler = { [weak self] proc in
                // Drain any remaining partial lines
                ioQueue.sync {
                    flushBuffer(&stdoutBuffer, prefix: "")
                    flushBuffer(&stderrBuffer, prefix: "[stderr] ")
                }
                continuation.yield("[spur] Process exited with code \(proc.terminationStatus).")
                continuation.finish()

                self?.serversLock.lock()
                self?.servers.removeValue(forKey: optionId)
                self?.serversLock.unlock()
                logger.info("Dev server for option \(optionId) exited (code \(proc.terminationStatus))")
            }

            do {
                try process.run()
            } catch {
                continuation.yield("[spur] Failed to launch: \(error.localizedDescription)")
                continuation.finish()
                logger.error("Failed to start dev server for option \(optionId): \(error.localizedDescription)")
                return
            }

            // Move the child to its own process group so we can kill it and all its
            // children (e.g., webpack, esbuild) with kill(-pgid, ...).
            let pid = process.processIdentifier
            setpgid(pid, pid)

            serversLock.lock()
            servers[optionId] = RunningServer(process: process, continuation: continuation)
            serversLock.unlock()

            logger.info("Dev server started for option \(optionId) pid=\(pid) port=\(port)")

            // Stop server if consumer cancels the stream
            continuation.onTermination = { [weak self] _ in
                self?.terminateGracefully(optionId: optionId)
            }
        }
    }

    /// Stops the dev server for `optionId`. Sends SIGTERM, then SIGKILL after the kill timeout.
    func stop(optionId: UUID) async throws {
        serversLock.lock()
        let server = servers[optionId]
        serversLock.unlock()

        guard server != nil else { throw DevServerError.notRunning(optionId) }
        terminateGracefully(optionId: optionId)
    }

    func isRunning(optionId: UUID) -> Bool {
        serversLock.lock()
        defer { serversLock.unlock() }
        return servers[optionId] != nil
    }

    /// Stops all running servers. Called on app termination and in `deinit`.
    func stopAll() {
        serversLock.lock()
        let ids = Array(servers.keys)
        serversLock.unlock()

        for id in ids {
            terminateGracefully(optionId: id)
        }
    }

    // MARK: - Private helpers

    private func terminateGracefully(optionId: UUID) {
        serversLock.lock()
        let server = servers[optionId]
        serversLock.unlock()

        guard let server, server.process.isRunning else { return }

        let pid = server.process.processIdentifier
        kill(-pid, SIGTERM)
        logger.debug("Sent SIGTERM to process group \(pid) (option \(optionId))")

        let deadline = Date(timeIntervalSinceNow: Constants.devServerKillTimeout)
        while server.process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        if server.process.isRunning {
            kill(-pid, SIGKILL)
            logger.warning("Sent SIGKILL to process group \(pid) (SIGTERM timed out)")
        }
    }

    /// Splits a command string into an argv array, respecting double-quoted segments.
    private func parseCommand(_ command: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false

        for char in command {
            switch char {
            case "\"":
                inQuotes.toggle()
            case " ", "\t" where !inQuotes:
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }
            default:
                current.append(char)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}
