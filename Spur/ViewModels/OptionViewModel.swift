import Foundation

// TODO: [Phase 3] Implement OptionViewModel — see agents.md Prompt 6.
// TODO: [Phase 4] Wire DevServerService for start/stop/logs.
// TODO: [Phase 5] Add Turn/Checkpoint/Fork logic.

@MainActor
final class OptionViewModel: ObservableObject {
    @Published var options: [SpurOption] = []
    @Published var selectedOption: SpurOption?
    @Published var isLoading = false
    @Published var error: Error?

    // TODO: Inject GitService, DevServerService, PersistenceService.
}
