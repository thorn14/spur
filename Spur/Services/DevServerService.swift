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
        let pty: PTYProcess
        let continuation: AsyncStream<String>.Continuation
    }

    // MARK: - State

    /// State is protected by `OSAllocatedUnfairLock`, which — unlike `NSLock` —
    /// is safe to call from async contexts.
    private let state = OSAllocatedUnfairLock(initialState: [UUID: RunningServer]())

    deinit {
        killAll()
    }

    // MARK: - Public API

    /// Starts a dev server for `optionId`. Returns an `AsyncStream` of log lines.
    /// Callers should check `isRunning` before calling to avoid `.alreadyRunning` errors.
    func start(
        optionId: UUID,
        worktreePath: String,
        port: Int,
        command: String = Constants.defaultDevCommand
    ) -> AsyncStream<String> {
        let alreadyRunning = state.withLock { $0[optionId] != nil }

        guard !alreadyRunning else {
            return AsyncStream { continuation in
                continuation.yield("[spur] Error: server already running for this option.")
                continuation.finish()
            }
        }

        guard !command.trimmingCharacters(in: .whitespaces).isEmpty else {
            return AsyncStream { continuation in
                continuation.yield("[spur] Error: empty command — cannot start dev server.")
                continuation.finish()
            }
        }

        let worktreeURL = URL(fileURLWithPath: worktreePath)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            let pty: PTYProcess
            do {
                pty = try PTYProcess()
            } catch {
                continuation.yield("[spur] Failed to open PTY: \(error.localizedDescription)")
                continuation.finish()
                logger.error("PTY open failed for option \(optionId): \(error.localizedDescription)")
                return
            }

            let environment: [String: String] = [
                "PORT": "\(port)",
                "FORCE_COLOR": "0",
                "TERM": "xterm-256color"
            ]

            do {
                try pty.launch(
                    shell: shell,
                    arguments: ["-l", "-i", "-c", command],
                    environment: environment,
                    workingDirectory: worktreeURL
                )
            } catch {
                continuation.yield("[spur] Failed to launch: \(error.localizedDescription)")
                continuation.finish()
                logger.error("Failed to start dev server for option \(optionId): \(error.localizedDescription)")
                return
            }

            state.withLock { $0[optionId] = RunningServer(pty: pty, continuation: continuation) }

            logger.info("Dev server started for option \(optionId) port=\(port)")

            // Forward PTY output to the stream continuation.
            Task { [weak self] in
                for await line in pty.outputStream() {
                    continuation.yield(line)
                }
                // PTY output loop ended — process has exited.
                continuation.finish()
                self?.state.withLock { $0[optionId] = nil }
                logger.info("Dev server for option \(optionId) exited")
            }

            // Stop server if consumer cancels the stream.
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.terminateGracefully(optionId: optionId)
                }
            }
        }
    }

    /// Stops the dev server for `optionId`. Sends SIGTERM, then SIGKILL after the kill timeout.
    func stop(optionId: UUID) async throws {
        guard isRunning(optionId: optionId) else { throw DevServerError.notRunning(optionId) }
        await terminateGracefully(optionId: optionId)
    }

    func isRunning(optionId: UUID) -> Bool {
        state.withLock { $0[optionId] != nil }
    }

    /// Stops all running servers. Called on app termination.
    /// Fires an unstructured Task so the caller does not have to be async.
    func stopAll() {
        let ids = state.withLock { Array($0.keys) }

        Task {
            for id in ids {
                await terminateGracefully(optionId: id)
            }
        }
    }

    // MARK: - Private helpers

    private func server(for optionId: UUID) -> RunningServer? {
        state.withLock { $0[optionId] }
    }

    private func terminateGracefully(optionId: UUID) async {
        guard let server = server(for: optionId) else { return }
        logger.debug("Terminating dev server for option \(optionId)")
        await server.pty.terminateGracefully()
    }

    /// Synchronous force-kill used only from `deinit`, where `async` is unavailable.
    private func killAll() {
        let all = state.withLock { $0 }
        for (optionId, server) in all {
            server.pty.forceKill()
            logger.debug("deinit: force-killed PTY for option \(optionId)")
        }
    }
}
