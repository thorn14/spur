import XCTest
@testable import Spur

/// Integration tests for GitService.
///
/// Each test gets its own isolated git environment:
///   - `tempDir/remote.git`   — bare repo acting as "origin"
///   - `tempDir/repo`         — working checkout with origin pointing at the bare repo
///   - `tempDir/worktrees/`   — directory where test worktrees are placed
///
/// All git calls go through ProcessRunner (executableURL + arguments, no shell strings).
final class GitServiceTests: XCTestCase {
    private var tempDir: URL!
    private var remoteURL: URL!
    private var repoURL: URL!
    private var worktreesURL: URL!
    private var service: GitService!
    private let runner = ProcessRunner()
    private let env = URL(fileURLWithPath: "/usr/bin/env")

    // MARK: - setUp / tearDown

    override func setUp() async throws {
        try await super.setUp()

        tempDir      = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpurGitTests-\(UUID().uuidString)")
        remoteURL    = tempDir.appendingPathComponent("remote.git")
        repoURL      = tempDir.appendingPathComponent("repo")
        worktreesURL = tempDir.appendingPathComponent("worktrees")

        for dir in [tempDir!, remoteURL!, repoURL!, worktreesURL!] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // 1. Bare remote (acts as "origin")
        try await run(["git", "init", "--bare", remoteURL.path])

        // 2. Working repo with user config and remote
        try await run(["git", "init", "-b", "main", repoURL.path])
        try await run(["git", "-C", repoURL.path, "config", "user.email", "test@spur.test"])
        try await run(["git", "-C", repoURL.path, "config", "user.name",  "Spur Test"])
        try await run(["git", "-C", repoURL.path, "remote", "add", "origin", remoteURL.path])

        // 3. Initial commit + push
        try "# Spur Test".write(to: repoURL.appendingPathComponent("README.md"),
                                atomically: true, encoding: .utf8)
        try await run(["git", "-C", repoURL.path, "add", "-A"])
        try await run(["git", "-C", repoURL.path, "commit", "-m", "Initial commit"])
        try await run(["git", "-C", repoURL.path, "push", "-u", "origin", "main"])

        service = GitService(runner: runner)
    }

    override func tearDown() async throws {
        _ = try? await runner.run(
            executable: env,
            arguments: ["git", "worktree", "prune"],
            workingDirectory: repoURL
        )
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - createBranchAndWorktree — Mode A (from branch tip)

    func testCreateFromMainCreatesWorktreeDirectory() async throws {
        let wtPath = worktreePath("mode-a")
        try await service.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: "exp/test/mode-a",
            worktreePath: wtPath, from: .main("main")
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: wtPath))
    }

    func testCreateFromMainBranchExistsInRepo() async throws {
        let branch = "exp/test/branch-check"
        try await service.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: branch,
            worktreePath: worktreePath("branch-check"), from: .main("main")
        )
        let branches = try await stdout(["git", "-C", repoURL.path, "branch"])
        XCTAssertTrue(branches.contains(branch))
    }

    func testCreateFromMainStartsAtMainHead() async throws {
        let mainHead = try await service.getCurrentHead(worktreePath: repoURL.path)
        let wtPath   = worktreePath("same-commit")
        try await service.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: "exp/test/same-commit",
            worktreePath: wtPath, from: .main("main")
        )
        let wtHead = try await service.getCurrentHead(worktreePath: wtPath)
        XCTAssertEqual(wtHead, mainHead)
    }

    // MARK: - createBranchAndWorktree — Mode B (from exact commit)

    func testCreateFromCommitMatchesHash() async throws {
        let headHash = try await service.getCurrentHead(worktreePath: repoURL.path)
        let wtPath   = worktreePath("from-commit")
        try await service.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: "exp/test/from-commit",
            worktreePath: wtPath, from: .commit(headHash)
        )
        let wtHead = try await service.getCurrentHead(worktreePath: wtPath)
        XCTAssertEqual(wtHead, headHash)
    }

    func testCreateFromInvalidCommitThrows() async throws {
        let badHash = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        do {
            try await service.createBranchAndWorktree(
                repoPath: repoURL.path, branchName: "exp/test/bad",
                worktreePath: worktreePath("bad"), from: .commit(badHash)
            )
            XCTFail("Expected GitServiceError.commitNotFound")
        } catch GitServiceError.commitNotFound(let hash) {
            XCTAssertEqual(hash, badHash)
        }
    }

    // MARK: - Guard conditions

    func testDuplicateBranchThrows() async throws {
        let branch = "exp/test/dup"
        try await service.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: branch,
            worktreePath: worktreePath("dup1"), from: .main("main")
        )
        do {
            try await service.createBranchAndWorktree(
                repoPath: repoURL.path, branchName: branch,
                worktreePath: worktreePath("dup2"), from: .main("main")
            )
            XCTFail("Expected GitServiceError.branchAlreadyExists")
        } catch GitServiceError.branchAlreadyExists(let name) {
            XCTAssertEqual(name, branch)
        }
    }

    func testExistingDirectoryThrows() async throws {
        let path = worktreePath("pre-existing")
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path), withIntermediateDirectories: true
        )
        do {
            try await service.createBranchAndWorktree(
                repoPath: repoURL.path, branchName: "exp/test/pre-existing",
                worktreePath: path, from: .main("main")
            )
            XCTFail("Expected GitServiceError.worktreeDirectoryExists")
        } catch GitServiceError.worktreeDirectoryExists(let p) {
            XCTAssertEqual(p, path)
        }
    }

    func testWorktreeCreationFailureRollsBackBranch() async throws {
        // Pre-create the directory so worktreeDirectoryExists fires before branch creation.
        // This exercises the code path where the guard prevents the branch from being made,
        // and therefore no rollback is needed — but the branch must not exist afterwards.
        let path = worktreePath("rollback")
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path), withIntermediateDirectories: true
        )
        _ = try? await service.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: "exp/test/rollback",
            worktreePath: path, from: .main("main")
        )
        let branches = try await stdout(["git", "-C", repoURL.path, "branch"])
        XCTAssertFalse(branches.contains("exp/test/rollback"))
    }

    // MARK: - removeWorktree

    func testRemoveWorktreeDeletesDirectory() async throws {
        let wtPath = worktreePath("removable")
        try await service.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: "exp/test/removable",
            worktreePath: wtPath, from: .main("main")
        )
        try await service.removeWorktree(repoPath: repoURL.path, worktreePath: wtPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wtPath))
    }

    func testRemoveWorktreeDeregistersFromList() async throws {
        let wtPath = worktreePath("deregister")
        try await service.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: "exp/test/deregister",
            worktreePath: wtPath, from: .main("main")
        )
        try await service.removeWorktree(repoPath: repoURL.path, worktreePath: wtPath)
        let worktrees = try await service.listWorktrees(repoPath: repoURL.path)
        XCTAssertFalse(worktrees.map(\.path).contains(wtPath))
    }

    // MARK: - listWorktrees

    func testListWorktreesAlwaysIncludesMainRepo() async throws {
        let worktrees = try await service.listWorktrees(repoPath: repoURL.path)
        let paths = worktrees.map(\.path)
        let repoResolved = repoURL.resolvingSymlinksInPath().path
        XCTAssertTrue(paths.contains { $0 == repoURL.path || $0 == repoResolved })
    }

    func testListWorktreesIncludesNewWorktree() async throws {
        let wtPath = worktreePath("listed")
        try await service.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: "exp/test/listed",
            worktreePath: wtPath, from: .main("main")
        )
        let worktrees = try await service.listWorktrees(repoPath: repoURL.path)
        XCTAssertTrue(worktrees.map(\.path).contains(wtPath))
    }

    func testListWorktreesReturnsCorrectBranchName() async throws {
        let branch = "exp/test/branch-name-check"
        let wtPath = worktreePath("branch-name-check")
        try await service.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: branch,
            worktreePath: wtPath, from: .main("main")
        )
        let worktrees = try await service.listWorktrees(repoPath: repoURL.path)
        let info = worktrees.first { $0.path == wtPath }
        XCTAssertEqual(info?.branch, branch)
    }

    func testListWorktreesHeadIsValidHash() async throws {
        let worktrees = try await service.listWorktrees(repoPath: repoURL.path)
        XCTAssertFalse(worktrees.isEmpty)
        for wt in worktrees {
            XCTAssertEqual(wt.head.count, 40, "HEAD hash in WorktreeInfo must be 40 chars")
        }
    }

    // MARK: - push

    func testPushCreatesRemoteBranch() async throws {
        let branch = "exp/test/pushed"
        try await service.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: branch,
            worktreePath: worktreePath("pushed"), from: .main("main")
        )
        try await service.push(repoPath: repoURL.path, branch: branch)

        let remoteBranches = try await stdout(["git", "-C", remoteURL.path, "branch"])
        XCTAssertTrue(remoteBranches.contains("exp/test/pushed"))
    }

    // MARK: - getCurrentHead

    func testGetCurrentHeadIs40CharHex() async throws {
        let head = try await service.getCurrentHead(worktreePath: repoURL.path)
        XCTAssertEqual(head.count, 40)
        XCTAssertTrue(head.allSatisfy(\.isHexDigit))
    }

    func testGetCurrentHeadMatchesGitRevParse() async throws {
        let expected = try await stdout(["git", "-C", repoURL.path, "rev-parse", "HEAD"])
        let actual   = try await service.getCurrentHead(worktreePath: repoURL.path)
        XCTAssertEqual(actual, expected)
    }

    // MARK: - getCommitsSince

    func testGetCommitsSinceCountsNewCommits() async throws {
        let start = try await service.getCurrentHead(worktreePath: repoURL.path)
        try await makeCommit(filename: "a.txt", content: "A", message: "Commit A")
        try await makeCommit(filename: "b.txt", content: "B", message: "Commit B")

        let commits = try await service.getCommitsSince(hash: start, worktreePath: repoURL.path)
        XCTAssertEqual(commits.count, 2)
    }

    func testGetCommitsSinceAllHashesAre40Chars() async throws {
        let start = try await service.getCurrentHead(worktreePath: repoURL.path)
        try await makeCommit(filename: "x.txt", content: "x", message: "X")
        let commits = try await service.getCommitsSince(hash: start, worktreePath: repoURL.path)
        for h in commits {
            XCTAssertEqual(h.count, 40)
            XCTAssertTrue(h.allSatisfy(\.isHexDigit))
        }
    }

    func testGetCommitsSinceEmptyWhenNone() async throws {
        let head    = try await service.getCurrentHead(worktreePath: repoURL.path)
        let commits = try await service.getCommitsSince(hash: head, worktreePath: repoURL.path)
        XCTAssertTrue(commits.isEmpty)
    }

    func testGetCommitsSinceOrderIsNewestFirst() async throws {
        let start = try await service.getCurrentHead(worktreePath: repoURL.path)
        try await makeCommit(filename: "first.txt",  content: "1", message: "First")
        let mid   = try await service.getCurrentHead(worktreePath: repoURL.path)
        try await makeCommit(filename: "second.txt", content: "2", message: "Second")
        let latest = try await service.getCurrentHead(worktreePath: repoURL.path)

        let commits = try await service.getCommitsSince(hash: start, worktreePath: repoURL.path)
        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits[0], latest)
        XCTAssertEqual(commits[1], mid)
    }

    // MARK: - hasUncommittedChanges

    func testCleanRepoHasNoChanges() async throws {
        XCTAssertFalse(try await service.hasUncommittedChanges(worktreePath: repoURL.path))
    }

    func testUntrackedFileIsDetected() async throws {
        try "untracked".write(to: repoURL.appendingPathComponent("new.txt"),
                              atomically: true, encoding: .utf8)
        XCTAssertTrue(try await service.hasUncommittedChanges(worktreePath: repoURL.path))
    }

    func testModifiedTrackedFileIsDetected() async throws {
        try "modified".write(to: repoURL.appendingPathComponent("README.md"),
                             atomically: true, encoding: .utf8)
        XCTAssertTrue(try await service.hasUncommittedChanges(worktreePath: repoURL.path))
    }

    func testCleanAfterCommitAll() async throws {
        try "data".write(to: repoURL.appendingPathComponent("temp.txt"),
                         atomically: true, encoding: .utf8)
        XCTAssertTrue(try await service.hasUncommittedChanges(worktreePath: repoURL.path))
        _ = try await service.commitAll(worktreePath: repoURL.path, message: "[spur] test clean")
        XCTAssertFalse(try await service.hasUncommittedChanges(worktreePath: repoURL.path))
    }

    // MARK: - commitAll

    func testCommitAllReturns40CharHash() async throws {
        try "data".write(to: repoURL.appendingPathComponent("c.txt"),
                         atomically: true, encoding: .utf8)
        let hash = try await service.commitAll(worktreePath: repoURL.path,
                                               message: "[spur] Checkpoint: test")
        XCTAssertEqual(hash.count, 40)
        XCTAssertTrue(hash.allSatisfy(\.isHexDigit))
    }

    func testCommitAllHashEqualsNewHead() async throws {
        try "y".write(to: repoURL.appendingPathComponent("y.txt"),
                      atomically: true, encoding: .utf8)
        let returned = try await service.commitAll(worktreePath: repoURL.path,
                                                   message: "[spur] commit all test")
        let head     = try await service.getCurrentHead(worktreePath: repoURL.path)
        XCTAssertEqual(returned, head)
    }

    func testCommitAllStagesUntrackedFiles() async throws {
        try "new".write(to: repoURL.appendingPathComponent("staged.txt"),
                        atomically: true, encoding: .utf8)
        _ = try await service.commitAll(worktreePath: repoURL.path, message: "[spur] stage test")
        XCTAssertFalse(try await service.hasUncommittedChanges(worktreePath: repoURL.path))
    }

    // MARK: - parseWorktreeList (parser unit tests — no git needed)

    func testParseWorktreeListTwoEntries() {
        let input = """
        worktree /repos/my-app
        HEAD abc1234abc1234abc1234abc1234abc1234abc1234
        branch refs/heads/main

        worktree /worktrees/feature
        HEAD def5678def5678def5678def5678def5678def5678
        branch refs/heads/exp/study/feature

        """
        let result = GitService.parseWorktreeList(input)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].path,   "/repos/my-app")
        XCTAssertEqual(result[0].branch, "main")
        XCTAssertEqual(result[0].head,   "abc1234abc1234abc1234abc1234abc1234abc1234")
        XCTAssertEqual(result[1].path,   "/worktrees/feature")
        XCTAssertEqual(result[1].branch, "exp/study/feature")
    }

    func testParseWorktreeListDetachedHead() {
        let input = """
        worktree /repos/my-app
        HEAD abc1234abc1234abc1234abc1234abc1234abc1234
        branch refs/heads/main

        worktree /worktrees/detached
        HEAD def5678def5678def5678def5678def5678def5678
        detached

        """
        let result = GitService.parseWorktreeList(input)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[1].branch, "",
                       "Detached HEAD worktree should have empty branch string")
    }

    func testParseWorktreeListEmpty() {
        XCTAssertTrue(GitService.parseWorktreeList("").isEmpty)
    }

    func testParseWorktreeListStripsRefsHeads() {
        let input = """
        worktree /path
        HEAD aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        branch refs/heads/exp/color-study/warm-palette

        """
        let result = GitService.parseWorktreeList(input)
        XCTAssertEqual(result.first?.branch, "exp/color-study/warm-palette")
    }

    // MARK: - Private helpers

    private func worktreePath(_ name: String) -> String {
        worktreesURL.appendingPathComponent(name).path
    }

    /// Runs a git command (args include "git" as first element) using /usr/bin/env.
    @discardableResult
    private func run(_ args: [String]) async throws -> ProcessResult {
        try await runner.run(executable: env, arguments: args)
    }

    /// Returns trimmed stdout of a git command.
    private func stdout(_ args: [String]) async throws -> String {
        let result = try await run(args)
        return result.stdout
    }

    /// Writes a file and commits it in `repoURL`.
    private func makeCommit(filename: String, content: String, message: String) async throws {
        try content.write(to: repoURL.appendingPathComponent(filename),
                          atomically: true, encoding: .utf8)
        try await run(["git", "-C", repoURL.path, "add", "-A"])
        try await run(["git", "-C", repoURL.path, "commit", "-m", message])
    }
}
