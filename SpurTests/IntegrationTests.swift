import XCTest
@testable import Spur

/// End-to-end integration tests covering multi-service workflows.
///
/// Each test uses an isolated git + persistence environment created in setUp.
///
/// Workflows tested:
///   1. Experiment → Option creation (branch + worktree on disk)
///   2. Turn lifecycle: start → capture checkpoint → fork
///   3. Command tokenizer with quotes (CommandRunnerViewModel.tokenize)
///   4. PRService.parseGitHubOwnerRepo (HTTPS + SSH remote URL formats)
///   5. Error paths: invalid repo, missing worktree, port in use
///   6. Reconciliation: delete worktree → reconcile → detached status
final class IntegrationTests: XCTestCase {

    // MARK: - Shared infrastructure

    private var tempDir: URL!
    private var remoteURL: URL!
    private var repoURL: URL!
    private var worktreesURL: URL!
    private var persistenceDir: URL!

    private var runner: ProcessRunner!
    private var git: GitService!
    private let env = URL(fileURLWithPath: "/usr/bin/env")

    override func setUp() async throws {
        try await super.setUp()

        let base     = FileManager.default.temporaryDirectory
        tempDir      = base.appendingPathComponent("SpurInteg-\(UUID().uuidString)")
        remoteURL    = tempDir.appendingPathComponent("remote.git")
        repoURL      = tempDir.appendingPathComponent("repo")
        worktreesURL = tempDir.appendingPathComponent("worktrees")
        persistenceDir = tempDir.appendingPathComponent("spur-state")

        for dir in [tempDir!, remoteURL!, repoURL!, worktreesURL!, persistenceDir!] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        try await run(["git", "init", "--bare", remoteURL.path])
        try await run(["git", "init", "-b", "main", repoURL.path])
        try await run(["git", "-C", repoURL.path, "config", "user.email", "test@spur.test"])
        try await run(["git", "-C", repoURL.path, "config", "user.name",  "Spur Test"])
        try await run(["git", "-C", repoURL.path, "remote", "add", "origin", remoteURL.path])

        try "# Spur Integration Test".write(
            to: repoURL.appendingPathComponent("README.md"),
            atomically: true, encoding: .utf8
        )
        try await run(["git", "-C", repoURL.path, "add", "-A"])
        try await run(["git", "-C", repoURL.path, "commit", "-m", "Initial commit"])
        try await run(["git", "-C", repoURL.path, "push", "-u", "origin", "main"])

        runner = ProcessRunner()
        git    = GitService(runner: runner)
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

    private func writeFile(name: String, content: String, in directory: URL) throws {
        try content.write(to: directory.appendingPathComponent(name),
                          atomically: true, encoding: .utf8)
    }

    // MARK: - 1. Branch + worktree creation (Option lifecycle)

    func testCreateOptionBranchAndWorktreeOnDisk() async throws {
        let branch   = "exp/color/warm"
        let wtPath   = worktreesURL.appendingPathComponent("warm").path

        try await git.createBranchAndWorktree(
            repoPath: repoURL.path,
            branchName: branch,
            worktreePath: wtPath,
            from: .main("main")
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: wtPath))

        let worktrees = try await git.listWorktrees(repoPath: repoURL.path)
        let paths = worktrees.map(\.path)
        XCTAssertTrue(paths.contains(wtPath), "Worktree should appear in list")
    }

    func testDuplicateBranchThrowsBranchAlreadyExists() async throws {
        let branch = "exp/test/dup"
        let wt1    = worktreesURL.appendingPathComponent("dup1").path

        try await git.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: branch,
            worktreePath: wt1, from: .main("main")
        )

        let wt2 = worktreesURL.appendingPathComponent("dup2").path
        do {
            try await git.createBranchAndWorktree(
                repoPath: repoURL.path, branchName: branch,
                worktreePath: wt2, from: .main("main")
            )
            XCTFail("Expected branchAlreadyExists error")
        } catch GitServiceError.branchAlreadyExists(let name) {
            XCTAssertEqual(name, branch)
        }
    }

    // MARK: - 2. Turn lifecycle

    func testStartTurnRecordsCurrentHead() async throws {
        let branch = "exp/turn/start"
        let wtPath = worktreesURL.appendingPathComponent("turn-start").path
        try await git.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: branch,
            worktreePath: wtPath, from: .main("main")
        )

        let head = try await git.getCurrentHead(worktreePath: wtPath)
        XCTAssertEqual(head.count, 40, "HEAD should be a full 40-char SHA")
    }

    func testCaptureCheckpointWithDirtyChanges() async throws {
        let branch = "exp/turn/checkpoint"
        let wtPath = worktreesURL.appendingPathComponent("checkpoint").path
        try await git.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: branch,
            worktreePath: wtPath, from: .main("main")
        )

        let startHead = try await git.getCurrentHead(worktreePath: wtPath)

        // Make a dirty change
        try writeFile(name: "change.txt", content: "hello", in: URL(fileURLWithPath: wtPath))
        let isDirty = try await git.hasUncommittedChanges(worktreePath: wtPath)
        XCTAssertTrue(isDirty)

        // Commit it (simulates captureCheckpoint)
        let endHash = try await git.commitAll(worktreePath: wtPath,
                                              message: "[spur] Checkpoint: Turn 1")
        let commits = try await git.getCommitsSince(hash: startHead, worktreePath: wtPath)

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0], endHash)
    }

    func testForkFromCheckpointUsesEndCommit() async throws {
        // Set up source option
        let srcBranch = "exp/fork/source"
        let srcPath   = worktreesURL.appendingPathComponent("fork-source").path
        try await git.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: srcBranch,
            worktreePath: srcPath, from: .main("main")
        )

        // Make a commit in the source worktree
        try writeFile(name: "feature.txt", content: "v1", in: URL(fileURLWithPath: srcPath))
        let checkpointHash = try await git.commitAll(worktreePath: srcPath,
                                                     message: "[spur] Checkpoint: Turn 1")

        // Fork from the checkpoint commit
        let forkBranch = "exp/fork/branch-b"
        let forkPath   = worktreesURL.appendingPathComponent("fork-b").path
        try await git.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: forkBranch,
            worktreePath: forkPath, from: .commit(checkpointHash)
        )

        // The fork's HEAD should equal the checkpoint
        let forkHead = try await git.getCurrentHead(worktreePath: forkPath)
        XCTAssertEqual(forkHead, checkpointHash,
                       "Forked worktree HEAD should match the checkpoint commit")

        // The forked file should exist
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: (forkPath as NSString).appendingPathComponent("feature.txt")
        ))
    }

    // MARK: - 3. CommandRunnerViewModel.tokenize

    func testTokenizeSimpleCommand() {
        let tokens = CommandRunnerViewModel.tokenize("npm run build")
        XCTAssertEqual(tokens, ["npm", "run", "build"])
    }

    func testTokenizeDoubleQuotes() {
        let tokens = CommandRunnerViewModel.tokenize(#"git commit -m "my commit message""#)
        XCTAssertEqual(tokens, ["git", "commit", "-m", "my commit message"])
    }

    func testTokenizeSingleQuotes() {
        let tokens = CommandRunnerViewModel.tokenize("echo 'hello world'")
        XCTAssertEqual(tokens, ["echo", "hello world"])
    }

    func testTokenizeEmptyString() {
        XCTAssertEqual(CommandRunnerViewModel.tokenize(""), [])
    }

    func testTokenizeExtraWhitespace() {
        let tokens = CommandRunnerViewModel.tokenize("  npm   install  ")
        XCTAssertEqual(tokens, ["npm", "install"])
    }

    func testTokenizeMixedQuotes() {
        let tokens = CommandRunnerViewModel.tokenize(#"curl -H 'Accept: application/json' "https://api.example.com""#)
        XCTAssertEqual(tokens, ["curl", "-H", "Accept: application/json", "https://api.example.com"])
    }

    // MARK: - 4. PRService.parseGitHubOwnerRepo

    func testParseHTTPSRemoteURL() {
        let result = PRService.parseGitHubOwnerRepo(from: "https://github.com/acme/my-app.git")
        XCTAssertEqual(result?.0, "acme")
        XCTAssertEqual(result?.1, "my-app")
    }

    func testParseHTTPSRemoteURLWithoutDotGit() {
        let result = PRService.parseGitHubOwnerRepo(from: "https://github.com/owner/repo")
        XCTAssertEqual(result?.0, "owner")
        XCTAssertEqual(result?.1, "repo")
    }

    func testParseSSHRemoteURL() {
        let result = PRService.parseGitHubOwnerRepo(from: "git@github.com:alice/cool-project.git")
        XCTAssertEqual(result?.0, "alice")
        XCTAssertEqual(result?.1, "cool-project")
    }

    func testParseNonGitHubURLReturnsNil() {
        XCTAssertNil(PRService.parseGitHubOwnerRepo(from: "https://gitlab.com/owner/repo.git"))
        XCTAssertNil(PRService.parseGitHubOwnerRepo(from: ""))
        XCTAssertNil(PRService.parseGitHubOwnerRepo(from: "not-a-url"))
    }

    func testParseRepoNameContainingDotGit() {
        // Repos whose names contain ".git" as an interior substring must not be corrupted.
        // e.g. "widget.git-tools" must not become "widget-tools".
        let https = PRService.parseGitHubOwnerRepo(from: "https://github.com/acme/widget.git-tools.git")
        XCTAssertEqual(https?.0, "acme")
        XCTAssertEqual(https?.1, "widget.git-tools")

        let ssh = PRService.parseGitHubOwnerRepo(from: "git@github.com:acme/widget.git-tools.git")
        XCTAssertEqual(ssh?.0, "acme")
        XCTAssertEqual(ssh?.1, "widget.git-tools")

        // Without trailing .git suffix the name must also survive intact.
        let httpsNoSuffix = PRService.parseGitHubOwnerRepo(from: "https://github.com/acme/widget.git-tools")
        XCTAssertEqual(httpsNoSuffix?.1, "widget.git-tools")
    }

    // MARK: - 5. Error paths

    func testGitServiceOnNonGitDirectoryThrows() async throws {
        let notARepo = tempDir.appendingPathComponent("not-a-repo").path
        try FileManager.default.createDirectory(atPath: notARepo,
                                                withIntermediateDirectories: true)

        do {
            _ = try await git.getCurrentHead(worktreePath: notARepo)
            XCTFail("Expected a GitServiceError")
        } catch is GitServiceError {
            // expected
        } catch {
            // Also acceptable — process runner error
        }
    }

    func testCommitNotFoundThrows() async throws {
        let badHash = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        let wtPath  = worktreesURL.appendingPathComponent("bad-commit").path

        do {
            try await git.createBranchAndWorktree(
                repoPath: repoURL.path, branchName: "exp/err/bad",
                worktreePath: wtPath, from: .commit(badHash)
            )
            XCTFail("Expected commitNotFound error")
        } catch GitServiceError.commitNotFound(let hash) {
            XCTAssertEqual(hash, badHash)
        }
    }

    // MARK: - 6. Reconciliation end-to-end

    func testReconcileAfterWorktreeDeletedMarksDetached() async throws {
        // Create option
        let branch = "exp/rec/gone"
        let wtPath = worktreesURL.appendingPathComponent("gone").path
        try await git.createBranchAndWorktree(
            repoPath: repoURL.path, branchName: branch,
            worktreePath: wtPath, from: .main("main")
        )

        // Verify the worktree is registered
        let beforeList = try await git.listWorktrees(repoPath: repoURL.path)
        XCTAssertTrue(beforeList.map(\.path).contains(wtPath))

        // Remove the worktree from disk (simulates manual deletion)
        try await git.removeWorktree(repoPath: repoURL.path, worktreePath: wtPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wtPath))

        // Build an AppState with the now-missing option
        let repo = Repo(path: repoURL.path)
        var state = AppState(repo: repo)
        state.options = [
            SpurOption(
                experimentId: UUID(),
                name: "Gone Option",
                slug: "gone",
                branchName: branch,
                worktreePath: wtPath,
                port: 3001
            )
        ]

        // Reconcile
        let reconciler = ReconciliationService(git: git)
        let changed = await reconciler.reconcile(appState: &state)

        XCTAssertEqual(changed, 1)
        XCTAssertEqual(state.options[0].status, .detached)
    }

    func testPersistenceRoundtripPreservesOptions() throws {
        let persistence = try PersistenceService(baseDirectory: persistenceDir)

        let repo = Repo(path: repoURL.path)
        var state = AppState(repo: repo)
        let experiment = Experiment(name: "My Exp", slug: "my-exp")
        state.experiments = [experiment]

        let option = SpurOption(
            experimentId: experiment.id,
            name: "Option A",
            slug: "option-a",
            branchName: "exp/my-exp/option-a",
            worktreePath: "/tmp/worktree",
            port: 3001
        )
        state.options = [option]

        try persistence.save(state)
        let loaded = try persistence.load(repoId: repo.id)

        XCTAssertEqual(loaded.experiments.count, 1)
        XCTAssertEqual(loaded.options.count, 1)
        XCTAssertEqual(loaded.options[0].name, "Option A")
        XCTAssertEqual(loaded.options[0].branchName, "exp/my-exp/option-a")
    }
}
