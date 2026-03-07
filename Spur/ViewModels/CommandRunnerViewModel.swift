import Foundation

// TODO: [Phase 6] Implement CommandRunnerViewModel — see agents.md Prompt 9.
// Parses command strings into executable + arguments (respecting quotes),
// runs via ProcessRunner in the Option's worktree cwd.

@MainActor
final class CommandRunnerViewModel: ObservableObject {
    @Published var outputLines: [String] = []
    @Published var isRunning = false
    @Published var error: Error?

    // TODO: Inject ProcessRunner.
}
