import Foundation

// TODO: [Phase 4] Implement DevServerService — see agents.md Prompt 7.

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

final class DevServerService {
    // TODO: [Phase 4] Implement. Track running processes by option ID.
    // Use process groups (setpgid) so child processes are killed with the parent.
    // Clean up all processes in deinit and applicationWillTerminate.

    func start(
        optionId: UUID,
        worktreePath: String,
        port: Int,
        command: String = Constants.defaultDevCommand
    ) -> AsyncStream<String> {
        // TODO
        return AsyncStream { continuation in continuation.finish() }
    }

    func stop(optionId: UUID) async throws {
        // TODO: Send SIGTERM, then SIGKILL after Constants.devServerKillTimeout
    }

    func isRunning(optionId: UUID) -> Bool {
        // TODO
        return false
    }
}
