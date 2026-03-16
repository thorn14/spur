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
        repoViewModel.$appState
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Prototype switching

    func setPrototype(_ prototype: Prototype?) {
        currentPrototypeId = prototype?.id
        objectWillChange.send()
        if let sel = selectedOption, sel.prototypeId != prototype?.id {
            selectedOptionId = nil
        }
    }

    // MARK: - Option creation

    /// Creates a branch+worktree, pushes it, installs dependencies, and auto-starts the first turn.
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

        await installDependencies(in: worktreePath, repoPath: repoPath)

        var option = SpurOption(
            prototypeId: prototype.id, name: trimmed, slug: optionSlug,
            branchName: branchName, worktreePath: worktreePath, port: port
        )
        let repoDevCmd = repoViewModel.appState?.devCommand ?? ""
        if !repoDevCmd.isEmpty { option.devCommand = repoDevCmd }
        repoViewModel.appState?.options.append(option)
        if let idx = repoViewModel.appState?.prototypes.firstIndex(where: { $0.id == prototype.id }) {
            repoViewModel.appState?.prototypes[idx].optionIds.append(option.id)
        }
        repoViewModel.persistState()
        selectedOptionId = option.id
        logger.info("Created option '\(trimmed)' branch='\(branchName)' port=\(port)")

        // Auto-start the first turn so recording begins immediately.
        await startTurnInternal(for: option, isAutomatic: true)
    }

    // MARK: - Dependency installation

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

    func startServer() {
        guard let option = selectedOption else { return }
        guard !devServer.isRunning(optionId: option.id) else { return }

        error = nil
        updateOptionStatus(option.id, status: .running)
        serverLogs[option.id] = []

        let repoDevCmd = repoViewModel.appState?.devCommand ?? ""
        let command: String
        if option.devCommand == Constants.defaultDevCommand && !repoDevCmd.isEmpty {
            command = repoDevCmd
        } else {
            command = option.devCommand
        }
        let stream = devServer.start(
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
                if self.detectedServerURLs[id] == nil,
                   let url = Self.extractLocalURL(from: line) {
                    self.detectedServerURLs[id] = url
                    logger.info("Detected server URL for option \(id): \(url)")
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.streamingTasks.removeValue(forKey: id)
                self.detectedServerURLs.removeValue(forKey: id)
                self.updateOptionStatus(id, status: .idle)
                logger.info("Dev server stream ended for option \(id)")
            }
        }
    }

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

    func stopAllServers() {
        devServer.stopAll()
    }

    func updateDevCommand(_ command: String, for optionId: UUID) {
        guard let idx = repoViewModel.appState?.options.firstIndex(where: { $0.id == optionId }) else { return }
        repoViewModel.appState?.options[idx].devCommand = command
        repoViewModel.persistState()
        objectWillChange.send()
    }

    func removeOption(_ optionId: UUID) {
        Task {
            if devServer.isRunning(optionId: optionId) {
                try? await devServer.stop(optionId: optionId)
            }
            if let option = repoViewModel.appState?.options.first(where: { $0.id == optionId }),
               let repoPath = repoViewModel.currentRepo?.path {
                try? await git.removeWorktree(repoPath: repoPath, worktreePath: option.worktreePath)
            }
            guard let idx = repoViewModel.appState?.options.firstIndex(where: { $0.id == optionId }) else { return }
            repoViewModel.appState?.options.remove(at: idx)
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

    /// Ensures each non-detached option has an open (uncaptured) turn so recording is
    /// always active. Call after `reconcileWorktrees()` on app launch.
    func resumeTurns() async {
        guard let options = repoViewModel.appState?.options else { return }
        var resumed = 0
        for option in options where option.status != .detached {
            let hasOpenTurn = option.turns.last.map { $0.endCommit == nil } ?? false
            if !hasOpenTurn {
                await startTurnInternal(for: option, isAutomatic: true)
                resumed += 1
            }
        }
        if resumed > 0 {
            logger.info("Resumed turns for \(resumed) option(s)")
        }
    }

    // MARK: - PR creation

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
        if let idx = repoViewModel.appState?.options.firstIndex(where: { $0.id == option.id }) {
            repoViewModel.appState?.options[idx].prURL = url
        }
        repoViewModel.persistState()
        objectWillChange.send()
        logger.info("PR created: \(url)")
        return url
    }

    // MARK: - Terminal

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

    func turns(for optionId: UUID) -> [Turn] {
        repoViewModel.appState?.options
            .first { $0.id == optionId }?.turns ?? []
    }

    /// The most recently captured (closed) turn for the given option, if any.
    func latestCapturedTurn(for optionId: UUID) -> Turn? {
        turns(for: optionId).last { $0.endCommit != nil }
    }

    // MARK: - Manual turn / checkpoint

    /// Manually starts a new turn for the selected option.
    func startTurn() async {
        guard let option = selectedOption else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        await startTurnInternal(for: option, isAutomatic: false)
    }

    /// Manually captures a checkpoint for the given turn (selected option).
    func captureCheckpoint(turn: Turn) async {
        guard let option = selectedOption else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        await performCheckpoint(turn: turn, option: option, isAutomatic: false)
    }

    // MARK: - Auto-checkpoint (triggered by Enter in terminal)

    /// Called when the user presses Enter in the terminal. Captures a checkpoint of any
    /// uncommitted changes made since the last checkpoint, then opens the next turn.
    func snapshotBeforeCommand(for optionId: UUID) {
        Task {
            guard let option = allOptions.first(where: { $0.id == optionId }),
                  option.status != .detached else { return }

            // If no open turn exists, start one — the current command will be recorded
            // in the next Enter-press checkpoint.
            guard let openTurn = option.turns.last, openTurn.endCommit == nil else {
                await startTurnInternal(for: option, isAutomatic: true)
                return
            }

            // Only capture if there are actual changes to snapshot.
            do {
                guard try await git.hasUncommittedChanges(worktreePath: option.worktreePath) else { return }
            } catch {
                logger.debug("snapshotBeforeCommand: hasUncommittedChanges failed for \(optionId): \(error)")
                return
            }

            await performCheckpoint(turn: openTurn, option: option, isAutomatic: true)
        }
    }

    // MARK: - Fork (New Exploration)

    /// Creates a new Option branched from `turn.endCommit` in the given prototype.
    func forkFromCheckpoint(turn: Turn, name: String, prototype: Prototype) async {
        guard let endCommit = turn.endCommit else {
            logger.error("forkFromCheckpoint: turn has no endCommit")
            return
        }
        await createOption(name: name, prototype: prototype, source: .commit(endCommit))
    }

    // MARK: - Rollback

    /// Hard-resets the worktree to `turn.endCommit`, discarding all later commits and
    /// uncommitted changes. Closes any open turn and starts a fresh one at the reset HEAD.
    func rollbackToCheckpoint(turn: Turn) async {
        guard let option = selectedOption,
              let endCommit = turn.endCommit else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // 1. Hard reset to the checkpoint commit
            try await git.resetWorktree(worktreePath: option.worktreePath, toCommit: endCommit)

            // 2. Close any open turn (mark it as rolled back)
            if let openTurn = option.turns.last, openTurn.endCommit == nil {
                let head = try await git.getCurrentHead(worktreePath: option.worktreePath)
                updateTurn(openTurn.id, in: option.id) { t in
                    t.endCommit = head
                    t.commitRange = []
                }
            }

            // 3. Start a fresh turn from the reset HEAD
            if let updatedOption = allOptions.first(where: { $0.id == option.id }) {
                await startTurnInternal(for: updatedOption, isAutomatic: true)
            }

            // 4. Push the reset state
            if let repoPath = repoViewModel.currentRepo?.path {
                do {
                    try await git.push(repoPath: repoPath, branch: option.branchName)
                } catch {
                    logger.error("Push after rollback failed: \(error.localizedDescription)")
                }
            }

            logger.info("Rolled back option \(option.id) to \(endCommit)")
        } catch {
            self.error = error
            logger.error("rollbackToCheckpoint failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private helpers

    /// Core checkpoint logic: commit dirty changes, record commit range, push, open next turn.
    private func performCheckpoint(turn: Turn, option: SpurOption, isAutomatic: Bool) async {
        do {
            if try await git.hasUncommittedChanges(worktreePath: option.worktreePath) {
                let message = isAutomatic
                    ? "[spur] Auto-checkpoint"
                    : "[spur] Checkpoint: \(turn.label)"
                _ = try await git.commitAll(worktreePath: option.worktreePath, message: message)
            }

            let commits = try await git.getCommitsSince(
                hash: turn.startCommit,
                worktreePath: option.worktreePath
            )
            let endCommit = try await git.getCurrentHead(worktreePath: option.worktreePath)

            // Skip if nothing actually changed since turn start for automatic checkpoints only.
            if endCommit == turn.startCommit && commits.isEmpty {
                if isAutomatic {
                    logger.debug("performCheckpoint: no changes since turn \(turn.number) start, skipping auto-checkpoint")
                    return
                } else {
                    logger.info("performCheckpoint: no changes since turn \(turn.number) start, closing manual checkpoint with empty commit range")
                }
            }

            updateTurn(turn.id, in: option.id) { t in
                t.endCommit = endCommit
                t.commitRange = commits
            }

            if let repoPath = repoViewModel.currentRepo?.path {
                do {
                    try await git.push(repoPath: repoPath, branch: option.branchName)
                } catch {
                    logger.error("Push after checkpoint failed: \(error.localizedDescription)")
                }
            }

            logger.info("Captured \(isAutomatic ? "auto-" : "")checkpoint for turn \(turn.number): \(endCommit)")
        } catch {
            if !isAutomatic { self.error = error }
            logger.error("performCheckpoint failed for option \(option.id): \(error.localizedDescription)")
        }
    }

    private func startTurnInternal(for option: SpurOption, isAutomatic: Bool) async {
        do {
            let head = try await git.getCurrentHead(worktreePath: option.worktreePath)
            let number = option.turns.count + 1
            let turn = Turn(number: number, label: "Turn \(number)", startCommit: head, isAutomatic: isAutomatic)
            appendTurn(turn, to: option.id)
            logger.info("Started turn \(number) at \(head) for option \(option.id) (auto=\(isAutomatic))")
        } catch {
            if !isAutomatic { self.error = error }
            logger.error("startTurnInternal failed for option \(option.id): \(error.localizedDescription)")
        }
    }

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

    static func extractLocalURL(from line: String) -> URL? {
        let pattern = #"https?://(localhost|127\.0\.0\.1):\d+"#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        return URL(string: String(line[range]))
    }
}
