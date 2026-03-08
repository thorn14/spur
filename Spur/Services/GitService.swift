import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "GitService")

// MARK: - Errors

enum GitServiceError: Error, LocalizedError {
    case executableNotFound
    case commandFailed(String, Int32, String)   // subcommand, exitCode, stderr
    case branchAlreadyExists(String)
    case worktreeDirectoryExists(String)
    case commitNotFound(String)
    case notAGitRepo(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "git executable not found. Make sure git is installed."
        case .commandFailed(let cmd, let code, let stderr):
            let detail = stderr.isEmpty ? "" : ": \(stderr)"
            return "git \(cmd) failed (exit \(code))\(detail)"
        case .branchAlreadyExists(let name):
            return "Branch '\(name)' already exists."
        case .worktreeDirectoryExists(let path):
            return "Worktree directory already exists at \(path)."
        case .commitNotFound(let hash):
            return "Commit '\(hash)' not found in this repository."
        case .notAGitRepo(let path):
            return "\(path) is not a git repository."
        }
    }
}

// MARK: - Supporting types

/// The starting point for a new Option branch.
enum BranchSource {
    /// Branch from the tip of an existing branch (e.g., "main"). — Mode A in plan.md §2.2
    case main(String)
    /// Branch from a specific commit hash. — Mode B in plan.md §2.2
    case commit(String)
}

struct WorktreeInfo: Equatable {
    let path: String
    let branch: String   // short name (no refs/heads/ prefix)
    let head: String     // full SHA-1 commit hash
}

// MARK: - GitService

/// Provides all git operations Spur needs: branch + worktree management, commit
/// detection, and push. Every operation uses ProcessRunner with an explicit
/// executableURL + arguments array. Shell strings are never constructed.
final class GitService {
    private let runner: ProcessRunner
    /// /usr/bin/env is used to resolve git from the user's PATH without hardcoding a path.
    private let env = URL(fileURLWithPath: "/usr/bin/env")

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    // MARK: - Branch + Worktree creation

    /// Creates a new branch and a git worktree for it, following plan.md §2.2.
    ///
    /// - Mode A (`from: .main("main")`): branch from the tip of `baseBranch`.
    /// - Mode B (`from: .commit(hash)`): branch from an exact commit hash.
    ///
    /// Worktree is placed at `worktreePath` (outside the main repo per §2.4).
    func createBranchAndWorktree(
        repoPath: String,
        branchName: String,
        worktreePath: String,
        from source: BranchSource
    ) async throws {
        let startPoint: String
        switch source {
        case .main(let base):    startPoint = base
        case .commit(let hash):  startPoint = hash
        }

        logger.debug("createBranchAndWorktree: branch=\(branchName) from=\(startPoint)")

        // Guard: branch must not already exist
        let listResult = try await git(in: repoPath, args: ["branch", "--list", branchName])
        if !listResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GitServiceError.branchAlreadyExists(branchName)
        }

        // Guard: worktree directory must not exist
        if FileManager.default.fileExists(atPath: worktreePath) {
            throw GitServiceError.worktreeDirectoryExists(worktreePath)
        }

        // Create the branch
        let branchResult = try await git(in: repoPath, args: ["branch", branchName, startPoint])
        if branchResult.exitCode != 0 {
            let stderr = branchResult.stderr
            if stderr.contains("unknown revision") || stderr.contains("not a commit") ||
               stderr.contains("bad object") {
                throw GitServiceError.commitNotFound(startPoint)
            }
            throw GitServiceError.commandFailed("branch \(branchName) \(startPoint)",
                                                branchResult.exitCode, stderr)
        }

        // Create the worktree
        let wtResult = try await git(in: repoPath, args: ["worktree", "add", worktreePath, branchName])
        if wtResult.exitCode != 0 {
            // Roll back: delete the branch we just created
            _ = try? await git(in: repoPath, args: ["branch", "-D", branchName])
            throw GitServiceError.commandFailed("worktree add \(worktreePath)", wtResult.exitCode, wtResult.stderr)
        }

        logger.info("Created branch '\(branchName)' and worktree at '\(worktreePath)'")
    }

    // MARK: - Worktree removal

    /// Removes a worktree from the repo's worktree list and deletes its directory.
    func removeWorktree(repoPath: String, worktreePath: String) async throws {
        logger.debug("removeWorktree: \(worktreePath)")
        let result = try await git(in: repoPath, args: ["worktree", "remove", "--force", worktreePath])
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed("worktree remove \(worktreePath)", result.exitCode, result.stderr)
        }
        logger.info("Removed worktree at '\(worktreePath)'")
    }

    // MARK: - Worktree listing

    /// Returns all worktrees registered with this repo, parsed from `git worktree list --porcelain`.
    func listWorktrees(repoPath: String) async throws -> [WorktreeInfo] {
        let result = try await git(in: repoPath, args: ["worktree", "list", "--porcelain"])
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed("worktree list", result.exitCode, result.stderr)
        }
        return Self.parseWorktreeList(result.stdout)
    }

    // MARK: - Push

    /// Pushes `branch` to `origin`, setting the upstream tracking reference.
    func push(repoPath: String, branch: String) async throws {
        logger.debug("push: branch=\(branch)")
        let result = try await git(in: repoPath, args: ["push", "-u", "origin", branch])
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed("push origin \(branch)", result.exitCode, result.stderr)
        }
        logger.info("Pushed branch '\(branch)' to origin")
    }

    // MARK: - Commit queries

    /// Returns the full SHA-1 hash of HEAD in the given directory (repo or worktree).
    func getCurrentHead(worktreePath: String) async throws -> String {
        let result = try await git(in: worktreePath, args: ["rev-parse", "HEAD"])
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed("rev-parse HEAD", result.exitCode, result.stderr)
        }
        return result.stdout
    }

    /// Returns the full commit hashes of all commits between `hash` (exclusive) and HEAD (inclusive).
    /// Ordered newest-first (same as `git log`).
    func getCommitsSince(hash: String, worktreePath: String) async throws -> [String] {
        let result = try await git(in: worktreePath, args: ["log", "\(hash)..HEAD", "--format=%H"])
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed("log \(hash)..HEAD", result.exitCode, result.stderr)
        }
        return result.stdout
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Working tree state

    /// Returns `true` if the worktree has any staged or unstaged changes (tracked or untracked files).
    func hasUncommittedChanges(worktreePath: String) async throws -> Bool {
        let result = try await git(in: worktreePath, args: ["status", "--porcelain"])
        guard result.exitCode == 0 else {
            throw GitServiceError.commandFailed("status --porcelain", result.exitCode, result.stderr)
        }
        return !result.stdout.isEmpty
    }

    /// Stages all changes (`git add -A`) and commits with `message`.
    /// Returns the full SHA-1 hash of the new commit.
    func commitAll(worktreePath: String, message: String) async throws -> String {
        logger.debug("commitAll in '\(worktreePath)': \(message)")

        let addResult = try await git(in: worktreePath, args: ["add", "-A"])
        guard addResult.exitCode == 0 else {
            throw GitServiceError.commandFailed("add -A", addResult.exitCode, addResult.stderr)
        }

        let commitResult = try await git(in: worktreePath, args: ["commit", "-m", message])
        guard commitResult.exitCode == 0 else {
            throw GitServiceError.commandFailed("commit", commitResult.exitCode, commitResult.stderr)
        }

        let hash = try await getCurrentHead(worktreePath: worktreePath)
        logger.info("Committed in '\(worktreePath)': \(hash)")
        return hash
    }

    // MARK: - Internal helpers

    /// Runs a git command in the given directory via `/usr/bin/env git`.
    @discardableResult
    private func git(in path: String, args: [String]) async throws -> ProcessResult {
        try await runner.run(
            executable: env,
            arguments: ["git"] + args,
            workingDirectory: URL(fileURLWithPath: path)
        )
    }

    // MARK: - Worktree list parser

    /// Parses `git worktree list --porcelain` output into `[WorktreeInfo]`.
    ///
    /// Format (stanzas separated by blank lines):
    /// ```
    /// worktree /path/to/checkout
    /// HEAD abc1234...
    /// branch refs/heads/main
    /// ```
    static func parseWorktreeList(_ output: String) -> [WorktreeInfo] {
        var result: [WorktreeInfo] = []
        var path = ""
        var head = ""
        var branch = ""

        func flush() {
            guard !path.isEmpty else { return }
            result.append(WorktreeInfo(path: path, branch: branch, head: head))
            path = ""; head = ""; branch = ""
        }

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                flush()
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.hasPrefix("refs/heads/")
                    ? String(ref.dropFirst("refs/heads/".count))
                    : ref
            }
        }
        flush()
        return result
    }
}
