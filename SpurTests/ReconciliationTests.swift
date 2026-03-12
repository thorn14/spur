import XCTest
@testable import Spur

/// Tests for ReconciliationService.
///
/// Each test creates an isolated git environment:
///   - `tempDir/remote.git`  — bare remote
///   - `tempDir/repo`        — working checkout
///   - `tempDir/worktrees/`  — worktree directory
final class ReconciliationTests: XCTestCase {
    private var tempDir: URL!
    private var remoteURL: URL!
    private var repoURL: URL!
    private var worktreesURL: URL!
    private var service: ReconciliationService!
    private var git: GitService!
    private let runner = ProcessRunner()
    private let env = URL(fileURLWithPath: "/usr/bin/env")

    // MARK: - setUp / tearDown

    override func setUp() async throws {
        try await super.setUp()

        tempDir      = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpurReconcileTests-\(UUID().uuidString)")
        remoteURL    = tempDir.appendingPathComponent("remote.git")
        repoURL      = tempDir.appendingPathComponent("repo")
        worktreesURL = tempDir.appendingPathComponent("worktrees")

        for dir in [tempDir!, remoteURL!, repoURL!, worktreesURL!] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        try await run(["git", "init", "--bare", remoteURL.path])
        try await run(["git", "init", "-b", "main", repoURL.path])
        try await run(["git", "-C", repoURL.path, "config", "user.email", "test@spur.test"])
        try await run(["git", "-C", repoURL.path, "config", "user.name",  "Spur Test"])
        try await run(["git", "-C", repoURL.path, "remote", "add", "origin", remoteURL.path])

        try "# Spur".write(to: repoURL.appendingPathComponent("README.md"),
                           atomically: true, encoding: .utf8)
        try await run(["git", "-C", repoURL.path, "add", "-A"])
        try await run(["git", "-C", repoURL.path, "commit", "-m", "init"])
        try await run(["git", "-C", repoURL.path, "push", "-u", "origin", "main"])

        git     = GitService(runner: runner)
        service = ReconciliationService(git: git)
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

    // MARK: - Helpers

    private func run(_ args: [String]) async throws {
        let result = try await runner.run(
            executable: env,
            arguments: args,
            workingDirectory: tempDir
        )
        guard result.exitCode == 0 else {
            throw XCTestError(.failureWhileWaiting,
                              userInfo: [NSLocalizedDescriptionKey: "git failed: \(result.stderr)"])
        }
    }

    private func makeState(options: [SpurOption] = []) -> AppState {
        let repo = Repo(path: repoURL.path)
        var state = AppState(repo: repo)
        state.options = options
        return state
    }

    private func makeOption(worktreePath: String, status: OptionStatus = .idle) -> SpurOption {
        SpurOption(
            prototypeId: UUID(),
            name: "test",
            slug: "test",
            branchName: "exp/test/test",
            worktreePath: worktreePath,
            port: 3001
        )
    }

    // MARK: - No options

    func testNoOptionsReturnsZeroChanges() async throws {
        var state = makeState()
        let changed = await service.reconcile(appState: &state)
        XCTAssertEqual(changed, 0)
    }

    // MARK: - All worktrees present

    func testAllWorktreesPresentNoChanges() async throws {
        // Create a real worktree
        let branch = "exp/test/present"
        let wtPath = worktreesURL.appendingPathComponent("present").path
        try await git.createBranchAndWorktree(
            repoPath: repoURL.path,
            branchName: branch,
            worktreePath: wtPath,
            from: .main("main")
        )

        var option = makeOption(worktreePath: wtPath)
        var state = makeState(options: [option])

        let changed = await service.reconcile(appState: &state)

        XCTAssertEqual(changed, 0)
        XCTAssertEqual(state.options[0].status, .idle)
    }

    // MARK: - Missing worktree → detached

    func testMissingWorktreeMarkedDetached() async throws {
        let missingPath = worktreesURL.appendingPathComponent("gone").path
        // Don't create the worktree — it does not exist
        var state = makeState(options: [makeOption(worktreePath: missingPath)])

        let changed = await service.reconcile(appState: &state)

        XCTAssertEqual(changed, 1)
        XCTAssertEqual(state.options[0].status, .detached)
    }

    func testMultipleOptions_OneMissingOnePresent() async throws {
        // Create one real worktree
        let presentPath = worktreesURL.appendingPathComponent("present").path
        try await git.createBranchAndWorktree(
            repoPath: repoURL.path,
            branchName: "exp/test/present",
            worktreePath: presentPath,
            from: .main("main")
        )

        let missingPath = worktreesURL.appendingPathComponent("gone").path
        var state = makeState(options: [
            makeOption(worktreePath: presentPath),
            makeOption(worktreePath: missingPath)
        ])

        let changed = await service.reconcile(appState: &state)

        XCTAssertEqual(changed, 1)
        XCTAssertEqual(state.options[0].status, .idle)
        XCTAssertEqual(state.options[1].status, .detached)
    }

    // MARK: - Running option not touched

    func testRunningOptionNotMarkedDetachedEvenIfWorktreeMissing() async throws {
        let missingPath = worktreesURL.appendingPathComponent("gone").path
        var option = makeOption(worktreePath: missingPath)
        option.status = .running
        var state = makeState(options: [option])

        let changed = await service.reconcile(appState: &state)

        XCTAssertEqual(changed, 0)
        XCTAssertEqual(state.options[0].status, .running, "Running options must not be touched")
    }

    // MARK: - Detached restored when worktree returns

    func testDetachedOptionRestoredWhenWorktreeExists() async throws {
        let wtPath = worktreesURL.appendingPathComponent("restored").path
        try await git.createBranchAndWorktree(
            repoPath: repoURL.path,
            branchName: "exp/test/restored",
            worktreePath: wtPath,
            from: .main("main")
        )

        var option = makeOption(worktreePath: wtPath)
        option.status = .detached  // simulate previously marked detached
        var state = makeState(options: [option])

        let changed = await service.reconcile(appState: &state)

        XCTAssertEqual(changed, 1)
        XCTAssertEqual(state.options[0].status, .idle)
    }

    // MARK: - Empty repo path

    func testEmptyRepoPathReturnsZero() async throws {
        let repo = Repo(path: "")
        var state = AppState(repo: repo)
        state.options = [makeOption(worktreePath: "/some/path")]

        let changed = await service.reconcile(appState: &state)
        XCTAssertEqual(changed, 0)
    }

    // MARK: - Symlink normalization

    /// Git reports canonical real paths (e.g. /private/var/…) while the persisted
    /// worktreePath may have retained a symlinked prefix (e.g. /var/…). Without
    /// normalization, the option would be wrongly marked .detached on macOS.
    func testSymlinkedWorktreePathNotMarkedDetached() async throws {
        let branch  = "exp/test/symlinked"
        let realURL = worktreesURL.appendingPathComponent("real-wt")
        try await git.createBranchAndWorktree(
            repoPath: repoURL.path,
            branchName: branch,
            worktreePath: realURL.path,
            from: .main("main")
        )

        // Create a symlink that points to the real worktree directory.
        let linkURL = worktreesURL.appendingPathComponent("link-wt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: realURL)

        // Persist the option using the symlinked path — as if the user's repo
        // was accessed via a symlinked directory segment.
        var state = makeState(options: [makeOption(worktreePath: linkURL.path)])

        let changed = await service.reconcile(appState: &state)

        XCTAssertEqual(changed, 0, "Symlinked worktree path must not be marked detached")
        XCTAssertEqual(state.options[0].status, .idle)
    }

    // MARK: - Idempotency

    func testReconcileIsIdempotent() async throws {
        let missingPath = worktreesURL.appendingPathComponent("gone").path
        var state = makeState(options: [makeOption(worktreePath: missingPath)])

        let first  = await service.reconcile(appState: &state)
        let second = await service.reconcile(appState: &state)

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0, "Second reconcile should find nothing new to change")
        XCTAssertEqual(state.options[0].status, .detached)
    }
}
