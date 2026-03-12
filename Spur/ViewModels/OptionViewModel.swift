import Combine
import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "OptionViewModel")

@MainActor
final class OptionViewModel: ObservableObject {
    // MARK: - Published state

    @Published var selectedOptionId: UUID?
    @Published var isLoading = false
    @Published var error: Error?
    /// Accumulated log lines per option ID.
    @Published var serverLogs: [UUID: [String]] = [:]
    /// Actual server URL detected from log output (overrides the allocated port).
    @Published var detectedServerURLs: [UUID: URL] = [:]

    // MARK: - Derived accessors

    /// Options belonging to the currently active prototype.
    var options: [SpurOption] {
        guard let id = currentPrototypeId else { return [] }
        return repoViewModel.appState?.options.filter { $0.prototypeId == id } ?? []
    }

    var selectedOption: SpurOption? {
        guard let id = selectedOptionId else { return nil }
        // Search allOptions so selection works across prototypes in the new sidebar.
        return allOptions.first { $0.id == id }
    }

    /// All options across all prototypes.
    var allOptions: [SpurOption] {
        repoViewModel.appState?.options ?? []
    }

    /// Returns the prototype owning the given option.
    func prototype(for option: SpurOption) -> Prototype? {
        repoViewModel.appState?.prototypes.first { $0.id == option.prototypeId }
    }

    /// Log lines for the currently selected option.
    var currentLogs: [String] {
        guard let id = selectedOptionId else { return [] }
        return serverLogs[id] ?? []
    }

    // MARK: - Dependencies

    private let repoViewModel: RepoViewModel
    private let git: GitService
    private let devServer: DevServerService
    private let prService: PRService
    private let terminalService: TerminalService
    private let reconciliationService: ReconciliationService
    private var currentPrototypeId: UUID?
    private var cancellables = Set<AnyCancellable>()
    /// Active streaming tasks, one per running option.
    private var streamingTasks: [UUID: Task<Void, Never>] = [:]

    init(
        repoViewModel: RepoViewModel,
        git: GitService,
        devServer: DevServerService,
        prService: PRService = PRService(),
        terminalService: TerminalService = TerminalService(),
        reconciliationService: ReconciliationService? = nil
    ) {
        self.repoViewModel = repoViewModel
        self.git = git
        self.devServer = devServer
        self.prService = prService
        self.terminalService = terminalService
        self.reconciliationService = reconciliationService ?? ReconciliationService(git: git)
        // Forward AppState mutations so views re-render when options list changes.
        repoViewModel.$appState
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Prototype switching

    /// Called by the workspace when the selected prototype changes.
    func setPrototype(_ prototype: Prototype?) {
        currentPrototypeId = prototype?.id
        objectWillChange.send()
        if let sel = selectedOption, sel.prototypeId != prototype?.id {
            selectedOptionId = nil
        }
    }

    // MARK: - Option creation

    /// Creates a branch+worktree for the new option, pushes it (Rule A), and persists.
    func createOption(name: String, prototype: Prototype, source: BranchSource) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let repoPath = repoViewModel.currentRepo?.path else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        let optionSlug   = SlugGenerator.generate(from: trimmed)
        let branchName   = "\(Constants.branchPrefix)/\(prototype.slug)/\(optionSlug)"
        let repoParent   = URL(fileURLWithPath: repoPath).deletingLastPathComponent().path
        let worktreePath = (repoParent as NSString)
            .appendingPathComponent("\(Constants.worktreeDirectoryName)/\(prototype.slug)--\(optionSlug)")

        let usedPorts = Set(repoViewModel.appState?.options.map(\.port) ?? [])
        guard let port = try? PortAllocator.allocate(excluding: usedPorts) else {
            error = PortAllocatorError.noPortsAvailable
            return
        }

        do {
            try await git.createBranchAndWorktree(
                repoPath: repoPath, branchName: branchName,
                worktreePath: worktreePath, from: source
            )
        } catch {
            self.error = error
            logger.error("createBranchAndWorktree failed: \(error.localizedDescription)")
            return
        }

        do {
            try await git.push(repoPath: repoPath, branch: branchName)
        } catch {
            logger.error("Push failed for '\(branchName)': \(error.localizedDescription)")
        }

        // Auto-install dependencies in the new worktree so the dev server works
        // without requiring a manual `pnpm install`. Uses the offline store cache
        // so subsequent installs are fast (no network required).
        await installDependencies(in: worktreePath, repoPath: repoPath)

        var option = SpurOption(
            prototypeId: prototype.id, name: trimmed, slug: optionSlug,
            branchName: branchName, worktreePath: worktreePath, port: port
        )
        // Inherit repo-level dev command if configured.
        let repoDevCmd = repoViewModel.appState?.devCommand ?? ""
        if !repoDevCmd.isEmpty { option.devCommand = repoDevCmd }
        repoViewModel.appState?.options.append(option)
        if let idx = repoViewModel.appState?.prototypes.firstIndex(where: { $0.id == prototype.id }) {
            repoViewModel.appState?.prototypes[idx].optionIds.append(option.id)
        }
        repoViewModel.persistState()
        selectedOptionId = option.id
        logger.info("Created option '\(trimmed)' branch='\(branchName)' port=\(port)")
    }

    // MARK: - Dependency installation

    /// Runs the repo's configured install command in `worktreePath`.
    /// Falls back to lockfile-detection if no command is saved yet.
    /// Failures are logged but do not block option creation.
    private func installDependencies(in worktreePath: String, repoPath: String) async {
        let saved = repoViewModel.appState?.installCommand ?? ""
        let cmd = saved.isEmpty
            ? Constants.packageManager(at: repoPath).installCommand
            : saved
        logger.info("Installing dependencies in worktree: \(cmd)")
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let worktreeURL = URL(fileURLWithPath: worktreePath)
        do {
            let pty = try PTYProcess()
            try pty.launch(
                shell: shell,
                arguments: ["-l", "-i", "-c", cmd],
                environment: ["TERM": "xterm-256color"],
                workingDirectory: worktreeURL
            )
            // Drain output so the process can make progress, but we don't surface
            // individual lines — just wait for exit and check the status.
            for await _ in pty.outputStream() {}
            let exitCode = pty.terminationStatus
            if exitCode == 0 {
                logger.info("Dependency install succeeded in \(worktreePath)")
            } else {
                logger.error("Dependency install failed (exit \(exitCode)) in \(worktreePath)")
            }
        } catch {
            logger.error("Dependency install threw: \(error.localizedDescription)")
        }
    }

    // MARK: - Dev server control

    /// Starts the dev server for the currently selected option.
    func startServer() {
        guard let option = selectedOption else { return }
        guard !devServer.isRunning(optionId: option.id) else { return }

        error = nil
        updateOptionStatus(option.id, status: .running)
        serverLogs[option.id] = []

        // Use the option-specific command unless it is still the generic default
        // and the repo has a configured command saved via RepoSetupSheet.
        let repoDevCmd = repoViewModel.appState?.devCommand ?? ""
        let command: String
        if option.devCommand == Constants.defaultDevCommand && !repoDevCmd.isEmpty {
            command = repoDevCmd
        } else {
            command = option.devCommand
        }
        let stream  = devServer.start(
            optionId: option.id,
            worktreePath: option.worktreePath,
            port: option.port,
            command: command
        )

        let id = option.id
        streamingTasks[id] = Task { [weak self] in
            for await line in stream {
                guard let self else { break }
                self.serverLogs[id, default: []].append(line)
                // Detect the actual bound URL from server output.
                // Matches patterns like: http://localhost:5173  or  http://127.0.0.1:3000
                if self.detectedServerURLs[id] == nil,
                   let url = Self.extractLocalURL(from: line) {
                    self.detectedServerURLs[id] = url
                    logger.info("Detected server URL for option \(id): \(url)")
                }
            }
            // Stream finished — server stopped
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.streamingTasks.removeValue(forKey: id)
                self.detectedServerURLs.removeValue(forKey: id)
                self.updateOptionStatus(id, status: .idle)
                logger.info("Dev server stream ended for option \(id)")
            }
        }
    }

    /// Stops the dev server for the currently selected option.
    ///
    /// Fire-and-forget: returns immediately; shutdown runs in an unstructured Task
    /// so the @MainActor is never suspended waiting for the (potentially 5-second)
    /// SIGTERM → SIGKILL drain sequence.
    func stopServer() {
        guard let option = selectedOption else { return }
        Task {
            do {
                try await devServer.stop(optionId: option.id)
            } catch {
                logger.error("Stop server failed: \(error.localizedDescription)")
                self.error = error
            }
        }
    }

    func isServerRunning(_ id: UUID) -> Bool {
        devServer.isRunning(optionId: id)
    }

    /// Stops all running servers (called on app termination).
    func stopAllServers() {
        devServer.stopAll()
    }

    /// Updates the dev command for the given option and persists.
    func updateDevCommand(_ command: String, for optionId: UUID) {
        guard let idx = repoViewModel.appState?.options.firstIndex(where: { $0.id == optionId }) else { return }
        repoViewModel.appState?.options[idx].devCommand = command
        repoViewModel.persistState()
        objectWillChange.send()
    }

    /// Stops the server (if running), removes the worktree, and deletes the option from state.
    func removeOption(_ optionId: UUID) {
        Task {
            if devServer.isRunning(optionId: optionId) {
                try? await devServer.stop(optionId: optionId)
            }

            // Remove git worktree
            if let option = repoViewModel.appState?.options.first(where: { $0.id == optionId }),
               let repoPath = repoViewModel.currentRepo?.path {
                try? await git.removeWorktree(repoPath: repoPath, worktreePath: option.worktreePath)
            }

            guard let idx = repoViewModel.appState?.options.firstIndex(where: { $0.id == optionId }) else { return }
            repoViewModel.appState?.options.remove(at: idx)

            // Remove from all prototype optionIds lists
            if let expIdx = repoViewModel.appState?.prototypes.firstIndex(where: {
                $0.optionIds.contains(optionId)
            }) {
                repoViewModel.appState?.prototypes[expIdx].optionIds.removeAll { $0 == optionId }
            }

            if selectedOptionId == optionId { selectedOptionId = options.first?.id }
            repoViewModel.persistState()
            objectWillChange.send()
            logger.info("Removed option \(optionId)")
        }
    }

    // MARK: - Reconciliation

    /// Compares persisted options against `git worktree list` and marks missing ones `.detached`.
    /// Called once on app launch after the repo state is loaded.
    func reconcileWorktrees() async {
        guard var state = repoViewModel.appState else { return }
        let changed = await reconciliationService.reconcile(appState: &state)
        if changed > 0 {
            repoViewModel.appState = state
            repoViewModel.persistState()
            objectWillChange.send()
            logger.info("Reconciliation marked \(changed) option(s) detached")
        }
    }

    // MARK: - PR creation

    /// Creates a PR for `option` and persists the result URL.
    @discardableResult
    func createPR(for option: SpurOption, title: String, body: String) async throws -> String {
        guard let repoPath = repoViewModel.currentRepo?.path else {
            throw PRServiceError.remoteNotFound
        }
        let url = try await prService.createPR(
            repoPath: repoPath,
            branch: option.branchName,
            title: title,
            body: body
        )
        // Persist URL on option
        if let idx = repoViewModel.appState?.options.firstIndex(where: { $0.id == option.id }) {
            repoViewModel.appState?.options[idx].prURL = url
        }
        repoViewModel.persistState()
        objectWillChange.send()
        logger.info("PR created: \(url)")
        return url
    }

    // MARK: - Terminal

    /// Opens Terminal.app at the selected option's worktree path.
    func openInTerminal() {
        guard let option = selectedOption else { return }
        do {
            try terminalService.openInTerminal(worktreePath: option.worktreePath)
        } catch {
            self.error = error
            logger.error("openInTerminal failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Turn management

    /// Returns turns for the given option, ordered by creation date.
    func turns(for optionId: UUID) -> [Turn] {
        repoViewModel.appState?.options
            .first { $0.id == optionId }?.turns ?? []
    }

    /// Starts a new Turn for the selected option by recording the current HEAD commit.
    func startTurn() async {
        guard let option = selectedOption else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let head = try await git.getCurrentHead(worktreePath: option.worktreePath)
            let number = option.turns.count + 1
            let turn = Turn(number: number, label: "Turn \(number)", startCommit: head)
            appendTurn(turn, to: option.id)
            logger.info("Started turn \(number) at \(head) for option \(option.id)")
        } catch {
            self.error = error
            logger.error("startTurn failed: \(error.localizedDescription)")
        }
    }

    /// Captures a checkpoint for the given turn:
    /// commits any dirty changes, records the commit range, pushes the branch.
    func captureCheckpoint(turn: Turn) async {
        guard let option = selectedOption else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // 1. Auto-commit dirty changes
            if try await git.hasUncommittedChanges(worktreePath: option.worktreePath) {
                _ = try await git.commitAll(
                    worktreePath: option.worktreePath,
                    message: "[spur] Checkpoint: \(turn.label)"
                )
            }

            // 2. Collect commits since turn start
            let commits = try await git.getCommitsSince(
                hash: turn.startCommit,
                worktreePath: option.worktreePath
            )
            let endCommit = try await git.getCurrentHead(worktreePath: option.worktreePath)

            // 3. Update turn
            updateTurn(turn.id, in: option.id) { t in
                t.endCommit = endCommit
                t.commitRange = commits
            }

            // 4. Push branch (Rule A) — pass the main repo path, not the worktree path,
            // consistent with all other push() call sites in this file.
            if let repoPath = repoViewModel.currentRepo?.path {
                do {
                    try await git.push(repoPath: repoPath, branch: option.branchName)
                } catch {
                    logger.error("Push after checkpoint failed: \(error.localizedDescription)")
                }
            }

            logger.info("Captured checkpoint for turn \(turn.number): \(endCommit)")
        } catch {
            self.error = error
            logger.error("captureCheckpoint failed: \(error.localizedDescription)")
        }
    }

    /// Creates a new Option branched from `turn.endCommit` in the given prototype.
    func forkFromCheckpoint(turn: Turn, name: String, prototype: Prototype) async {
        guard let endCommit = turn.endCommit else {
            logger.error("forkFromCheckpoint: turn has no endCommit")
            return
        }
        await createOption(name: name, prototype: prototype, source: .commit(endCommit))
    }

    // MARK: - Private helpers

    private func appendTurn(_ turn: Turn, to optionId: UUID) {
        guard let idx = repoViewModel.appState?.options.firstIndex(where: { $0.id == optionId }) else { return }
        repoViewModel.appState?.options[idx].turns.append(turn)
        repoViewModel.persistState()
        objectWillChange.send()
    }

    private func updateTurn(_ turnId: UUID, in optionId: UUID, mutation: (inout Turn) -> Void) {
        guard let optIdx = repoViewModel.appState?.options.firstIndex(where: { $0.id == optionId }),
              let turnIdx = repoViewModel.appState?.options[optIdx].turns.firstIndex(where: { $0.id == turnId })
        else { return }
        mutation(&repoViewModel.appState!.options[optIdx].turns[turnIdx])
        repoViewModel.persistState()
        objectWillChange.send()
    }

    private func updateOptionStatus(_ id: UUID, status: OptionStatus) {
        guard let idx = repoViewModel.appState?.options.firstIndex(where: { $0.id == id }) else { return }
        repoViewModel.appState?.options[idx].status = status
        repoViewModel.persistState()
        objectWillChange.send()
    }

    /// Scans a log line for a local server URL and returns it if found.
    /// Matches Vite, Next.js, webpack-dev-server, and most other dev servers.
    static func extractLocalURL(from line: String) -> URL? {
        // Match http://localhost:PORT or http://127.0.0.1:PORT
        let pattern = #"https?://(localhost|127\.0\.0\.1):\d+"#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        return URL(string: String(line[range]))
    }
}
