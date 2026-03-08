import Combine
import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "ExperimentViewModel")

@MainActor
final class ExperimentViewModel: ObservableObject {
    // MARK: - Published state

    /// ID of the currently selected experiment.
    @Published var selectedExperimentId: UUID?
    /// Non-nil when an operation fails.
    @Published var error: Error?

    // MARK: - Derived accessors (computed from AppState — no duplication)

    var experiments: [Experiment] {
        repoViewModel.appState?.experiments ?? []
    }

    var selectedExperiment: Experiment? {
        guard let id = selectedExperimentId else { return nil }
        return experiments.first { $0.id == id }
    }

    // MARK: - Dependencies

    private let repoViewModel: RepoViewModel
    private var cancellables = Set<AnyCancellable>()

    init(repoViewModel: RepoViewModel) {
        self.repoViewModel = repoViewModel
        // Forward AppState mutations so observing views re-render when experiments list changes.
        repoViewModel.$appState
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    /// Creates an experiment, persists it, and selects it immediately.
    func createExperiment(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        error = nil

        let slug = SlugGenerator.generate(from: trimmed)
        let experiment = Experiment(name: trimmed, slug: slug)
        repoViewModel.appState?.experiments.append(experiment)
        repoViewModel.persistState()
        selectedExperimentId = experiment.id
        logger.info("Created experiment '\(trimmed)' slug='\(slug)'")
    }
}
