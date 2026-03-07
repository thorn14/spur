import Foundation

// TODO: [Phase 2] Implement GitService — see agents.md Prompt 4 and plan.md §2.

enum GitServiceError: Error, LocalizedError {
    case executableNotFound
    case commandFailed(String, Int32)
    case branchAlreadyExists(String)
    case worktreeDirectoryExists(String)
    case commitNotFound(String)
    case notAGitRepo(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:               return "git executable not found."
        case .commandFailed(let cmd, let code): return "git \(cmd) failed with exit code \(code)."
        case .branchAlreadyExists(let name):    return "Branch '\(name)' already exists."
        case .worktreeDirectoryExists(let path):return "Worktree directory already exists at \(path)."
        case .commitNotFound(let hash):         return "Commit '\(hash)' not found."
        case .notAGitRepo(let path):            return "\(path) is not a git repository."
        }
    }
}

/// The starting point for a new branch.
enum BranchSource {
    /// Create from the tip of the named branch (e.g., "main").
    case main(String)
    /// Create from a specific commit hash.
    case commit(String)
}

struct WorktreeInfo {
    let path: String
    let branch: String
    let head: String
}

final class GitService {
    // TODO: [Phase 2] Implement all methods below.

    func createBranchAndWorktree(
        repoPath: String,
        branchName: String,
        worktreePath: String,
        from source: BranchSource
    ) async throws {
        // TODO
    }

    func removeWorktree(repoPath: String, worktreePath: String) async throws {
        // TODO
    }

    func listWorktrees(repoPath: String) async throws -> [WorktreeInfo] {
        // TODO
        return []
    }

    func push(repoPath: String, branch: String) async throws {
        // TODO
    }

    func getCurrentHead(worktreePath: String) async throws -> String {
        // TODO
        return ""
    }

    func getCommitsSince(hash: String, worktreePath: String) async throws -> [String] {
        // TODO
        return []
    }

    func hasUncommittedChanges(worktreePath: String) async throws -> Bool {
        // TODO
        return false
    }

    /// Stages all changes and commits them. Returns the new commit hash.
    func commitAll(worktreePath: String, message: String) async throws -> String {
        // TODO
        return ""
    }
}
