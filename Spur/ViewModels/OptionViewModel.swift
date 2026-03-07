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

    // MARK: - Derived accessors

    /// Options belonging to the currently active experiment.
    var options: [SpurOption] {
        guard let id = currentExperimentId else { return [] }
        return repoViewModel.appState?.options.filter { $0.experimentId == id } ?? []
    }

    var selectedOption: SpurOption? {
        guard let id = selectedOptionId else { return nil }
        return options.first { $0.id == id }
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
    private var currentExperimentId: UUID?
    private var cancellables = Set<AnyCancellable>()
    /// Active streaming tasks, one per running option.
    private var streamingTasks: [UUID: Task<Void, Never>] = [:]

    init(repoViewModel: RepoViewModel, git: GitService, devServer: DevServerService) {
        self.repoViewModel = repoViewModel
        self.git = git
        self.devServer = devServer
        // Forward AppState mutations so views re-render when options list changes.
        repoViewModel.$appState
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Experiment switching

    /// Called by the workspace when the selected experiment changes.
    func setExperiment(_ experiment: Experiment?) {
        currentExperimentId = experiment?.id
        objectWillChange.send()
        if let sel = selectedOption, sel.experimentId != experiment?.id {
            selectedOptionId = nil
        }
    }

    // MARK: - Option creation

    /// Creates a branch+worktree for the new option, pushes it (Rule A), and persists.
    func createOption(name: String, experiment: Experiment, source: BranchSource) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let repoPath = repoViewModel.currentRepo?.path else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        let optionSlug   = SlugGenerator.generate(from: trimmed)
        let branchName   = "\(Constants.branchPrefix)/\(experiment.slug)/\(optionSlug)"
        let repoParent   = URL(fileURLWithPath: repoPath).deletingLastPathComponent().path
        let worktreePath = (repoParent as NSString)
            .appendingPathComponent("\(Constants.worktreeDirectoryName)/\(experiment.slug)--\(optionSlug)")

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

        let option = SpurOption(
            experimentId: experiment.id, name: trimmed, slug: optionSlug,
            branchName: branchName, worktreePath: worktreePath, port: port
        )
        repoViewModel.appState?.options.append(option)
        if let idx = repoViewModel.appState?.experiments.firstIndex(where: { $0.id == experiment.id }) {
            repoViewModel.appState?.experiments[idx].optionIds.append(option.id)
        }
        repoViewModel.persistState()
        selectedOptionId = option.id
        logger.info("Created option '\(trimmed)' branch='\(branchName)' port=\(port)")
    }

    // MARK: - Dev server control

    /// Starts the dev server for the currently selected option.
    func startServer() {
        guard let option = selectedOption else { return }
        guard !devServer.isRunning(optionId: option.id) else { return }

        error = nil
        updateOptionStatus(option.id, status: .running)
        serverLogs[option.id] = []

        let command = repoViewModel.appState?.devCommand ?? Constants.defaultDevCommand
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
            }
            // Stream finished — server stopped
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.streamingTasks.removeValue(forKey: id)
                self.updateOptionStatus(id, status: .idle)
                logger.info("Dev server stream ended for option \(id)")
            }
        }
    }

    /// Stops the dev server for the currently selected option.
    func stopServer() async {
        guard let option = selectedOption else { return }
        do {
            try await devServer.stop(optionId: option.id)
        } catch {
            logger.error("Stop server failed: \(error.localizedDescription)")
            self.error = error
        }
    }

    func isServerRunning(_ id: UUID) -> Bool {
        devServer.isRunning(optionId: id)
    }

    /// Stops all running servers (called on app termination).
    func stopAllServers() {
        devServer.stopAll()
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

            // 4. Push branch (Rule A)
            do {
                try await git.push(repoPath: option.worktreePath, branch: option.branchName)
            } catch {
                logger.error("Push after checkpoint failed: \(error.localizedDescription)")
            }

            logger.info("Captured checkpoint for turn \(turn.number): \(endCommit)")
        } catch {
            self.error = error
            logger.error("captureCheckpoint failed: \(error.localizedDescription)")
        }
    }

    /// Creates a new Option branched from `turn.endCommit` in the given experiment.
    func forkFromCheckpoint(turn: Turn, name: String, experiment: Experiment) async {
        guard let endCommit = turn.endCommit else {
            logger.error("forkFromCheckpoint: turn has no endCommit")
            return
        }
        await createOption(name: name, experiment: experiment, source: .commit(endCommit))
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
}
