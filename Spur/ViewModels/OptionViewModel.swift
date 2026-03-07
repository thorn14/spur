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

    // MARK: - Dependencies

    private let repoViewModel: RepoViewModel
    private let git: GitService
    private var currentExperimentId: UUID?
    private var cancellables = Set<AnyCancellable>()

    init(repoViewModel: RepoViewModel, git: GitService) {
        self.repoViewModel = repoViewModel
        self.git = git
        // Forward AppState mutations so views re-render when options list changes.
        repoViewModel.$appState
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Experiment switching

    /// Called by the workspace when the selected experiment changes.
    /// Filters `options` to the new experiment and clears a stale tab selection.
    func setExperiment(_ experiment: Experiment?) {
        currentExperimentId = experiment?.id
        objectWillChange.send()
        // Clear selection if it belonged to the previous experiment.
        if let sel = selectedOption, sel.experimentId != experiment?.id {
            selectedOptionId = nil
        }
    }

    // MARK: - Option creation

    /// Creates a branch+worktree for the new option, pushes it (Rule A), and persists.
    ///
    /// - Parameters:
    ///   - name: User-provided option name (will be slugified).
    ///   - experiment: Parent experiment.
    ///   - source: `.main(baseBranch)` for Mode A, `.commit(hash)` for Mode B (Phase 5).
    func createOption(name: String, experiment: Experiment, source: BranchSource) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let repoPath = repoViewModel.currentRepo?.path else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        // Derive names and paths per plan.md §2.3 and §2.4.
        let optionSlug  = SlugGenerator.generate(from: trimmed)
        let branchName  = "\(Constants.branchPrefix)/\(experiment.slug)/\(optionSlug)"
        let repoParent  = URL(fileURLWithPath: repoPath).deletingLastPathComponent().path
        let worktreePath = (repoParent as NSString)
            .appendingPathComponent("\(Constants.worktreeDirectoryName)/\(experiment.slug)--\(optionSlug)")

        // Allocate a port, avoiding ports already held by other options.
        let usedPorts = Set(repoViewModel.appState?.options.map(\.port) ?? [])
        guard let port = try? PortAllocator.allocate(excluding: usedPorts) else {
            error = PortAllocatorError.noPortsAvailable
            return
        }

        // Create branch + worktree
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

        // Push (Rule A) — non-fatal: log but don't block the user on push failure.
        do {
            try await git.push(repoPath: repoPath, branch: branchName)
        } catch {
            logger.error("Push failed for '\(branchName)': \(error.localizedDescription)")
        }

        // Persist the new option and update its experiment's optionIds list.
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
}
