import Foundation

// TODO: [Phase 3] Implement ExperimentViewModel — see agents.md Prompt 6.

@MainActor
final class ExperimentViewModel: ObservableObject {
    @Published var experiments: [Experiment] = []
    @Published var selectedExperiment: Experiment?
    @Published var isLoading = false
    @Published var error: Error?

    // TODO: [Phase 3] Inject PersistenceService, GitService; implement create/select/delete.
}
