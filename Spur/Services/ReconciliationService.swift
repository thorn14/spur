import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "ReconciliationService")

/// Reconciles the persisted option list against the actual git worktrees on disk.
///
/// On app launch, a worktree can be missing because:
/// - The user manually deleted it.
/// - The directory was moved or renamed.
/// - The machine has changed since last run.
///
/// Options whose worktree path is absent from `git worktree list` are marked `.detached`.
/// Options previously marked `.detached` whose path reappears are restored to `.idle`.
final class ReconciliationService {
    private let git: GitService

    init(git: GitService = GitService()) {
        self.git = git
    }

    // MARK: - Public API

    /// Reconciles `appState.options` against actual worktrees.
    ///
    /// - Parameter appState: The state to mutate in-place.
    /// - Returns: The number of options whose status changed.
    @discardableResult
    func reconcile(appState: inout AppState) async -> Int {
        guard !appState.repoPath.isEmpty else { return 0 }

        let worktrees: [WorktreeInfo]
        do {
            worktrees = try await git.listWorktrees(repoPath: appState.repoPath)
        } catch {
            // Cannot list worktrees (not a git repo, git missing, etc.) — leave status unchanged.
            logger.error("Cannot list worktrees for reconciliation: \(error.localizedDescription)")
            return 0
        }

        let livePaths = Set(worktrees.map(\.path))
        var changedCount = 0

        for idx in appState.options.indices {
            let option = appState.options[idx]

            // Never mark a running option as detached — the server controls its own lifecycle.
            guard option.status != .running else { continue }

            let pathExists = livePaths.contains(option.worktreePath)

            if !pathExists && option.status != .detached {
                appState.options[idx].status = .detached
                changedCount += 1
                logger.warning("Worktree missing for option '\(option.name)': \(option.worktreePath)")
            } else if pathExists && option.status == .detached {
                appState.options[idx].status = .idle
                changedCount += 1
                logger.info("Worktree restored for option '\(option.name)': \(option.worktreePath)")
            }
        }

        if changedCount > 0 {
            logger.info("Reconciliation complete: \(changedCount) option(s) updated")
        } else {
            logger.debug("Reconciliation complete: all worktrees present")
        }
        return changedCount
    }
}
