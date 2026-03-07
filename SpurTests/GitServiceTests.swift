import XCTest
@testable import Spur

// TODO: [Phase 2] Implement GitServiceTests — see agents.md Prompt 5.
//
// Tests must use a temporary git repo (create bare remote + working repo in setUp,
// delete both in tearDown). Cover:
//   - createBranchAndWorktree(from: .main) — Mode A
//   - createBranchAndWorktree(from: .commit(hash)) — Mode B
//   - removeWorktree
//   - listWorktrees — accuracy and reconciliation
//   - push (using bare local repo as remote)
//   - getCurrentHead
//   - getCommitsSince
//   - hasUncommittedChanges
//   - commitAll
//
// All git operations use executableURL + arguments (no shell strings).

final class GitServiceTests: XCTestCase {
    // TODO: [Phase 2] Implement
}
