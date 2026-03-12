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
    /// Two-way sync:
    /// 1. Options whose worktree is missing → marked `.detached`
    /// 2. Worktrees on disk not in state   → imported as new options/prototypes
    ///
    /// - Returns: Total number of options whose status changed or were newly imported.
    @discardableResult
    func reconcile(appState: inout AppState) async -> Int {
        guard !appState.repoPath.isEmpty else { return 0 }

        let worktrees: [WorktreeInfo]
        do {
            worktrees = try await git.listWorktrees(repoPath: appState.repoPath)
        } catch {
            logger.error("Cannot list worktrees for reconciliation: \(error.localizedDescription)")
            return 0
        }

        func canonical(_ path: String) -> String {
            URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        }

        let livePaths = Set(worktrees.map { canonical($0.path) })
        var changedCount = 0

        // ── Pass 1: mark known options detached / restore them ──────────────
        for idx in appState.options.indices {
            let option = appState.options[idx]
            guard option.status != .running else { continue }
            let exists = livePaths.contains(canonical(option.worktreePath))
            if !exists && option.status != .detached {
                appState.options[idx].status = .detached
                changedCount += 1
                logger.warning("Worktree missing for option '\(option.name)'")
            } else if exists && option.status == .detached {
                appState.options[idx].status = .idle
                changedCount += 1
                logger.info("Worktree restored for option '\(option.name)'")
            }
        }

        // ── Pass 2: import unknown worktrees that match the spur branch pattern ──
        let knownPaths = Set(appState.options.map { canonical($0.worktreePath) })
        let repoCanonical = canonical(appState.repoPath)
        var usedPorts = Set(appState.options.map(\.port))

        for wt in worktrees {
            let wtCanonical = canonical(wt.path)
            // Skip the main repo worktree and anything already tracked.
            guard wtCanonical != repoCanonical,
                  !knownPaths.contains(wtCanonical) else { continue }

            // Only import branches that follow the spur naming convention:
            // exp/{prototype-slug}/{option-slug}
            guard let parsed = parseBranch(wt.branch) else {
                logger.debug("Skipping unrecognised branch '\(wt.branch)' at \(wt.path)")
                continue
            }

            // Find or create the prototype.
            let prototypeId: UUID
            if let existing = appState.prototypes.first(where: { $0.slug == parsed.prototypeSlug }) {
                prototypeId = existing.id
            } else {
                let proto = Prototype(
                    name: deslug(parsed.prototypeSlug),
                    slug: parsed.prototypeSlug
                )
                appState.prototypes.append(proto)
                prototypeId = proto.id
                logger.info("Imported prototype '\(proto.name)' during reconciliation")
            }

            // Allocate a port.
            let port = (try? PortAllocator.allocate(excluding: usedPorts)) ?? (3001 + usedPorts.count)
            usedPorts.insert(port)

            var option = SpurOption(
                prototypeId: prototypeId,
                name: deslug(parsed.optionSlug),
                slug: parsed.optionSlug,
                branchName: wt.branch,
                worktreePath: wt.path,
                port: port
            )
            option.status = .idle
            // Inherit the repo-level dev command so the option can be started immediately.
            if !appState.devCommand.isEmpty {
                option.devCommand = appState.devCommand
            }

            // Link option into its prototype.
            if let idx = appState.prototypes.firstIndex(where: { $0.id == prototypeId }) {
                appState.prototypes[idx].optionIds.append(option.id)
            }
            appState.options.append(option)
            changedCount += 1
            logger.info("Imported option '\(option.name)' (branch: \(wt.branch)) during reconciliation")
        }

        logger.info("Reconciliation complete: \(changedCount) change(s)")
        return changedCount
    }

    // MARK: - Helpers

    private struct ParsedBranch {
        let prototypeSlug: String
        let optionSlug: String
    }

    /// Parses `exp/{prototype-slug}/{option-slug}` → ParsedBranch, or nil if no match.
    private func parseBranch(_ branch: String) -> ParsedBranch? {
        let parts = branch.split(separator: "/", maxSplits: 3).map(String.init)
        guard parts.count == 3, parts[0] == Constants.branchPrefix else { return nil }
        return ParsedBranch(prototypeSlug: parts[1], optionSlug: parts[2])
    }

    /// Converts a slug like "test-colors" → "test colors" (display name).
    private func deslug(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ")
    }
}
