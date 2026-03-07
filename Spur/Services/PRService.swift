import Foundation

// TODO: [Phase 6] Implement PRService — see agents.md Prompt 9.

enum PRServiceError: Error, LocalizedError {
    case ghNotInstalled
    case ghNotAuthenticated
    case remoteNotFound
    case prCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .ghNotInstalled:           return "GitHub CLI (gh) is not installed. Opening browser instead."
        case .ghNotAuthenticated:       return "GitHub CLI not authenticated. Run 'gh auth login'."
        case .remoteNotFound:           return "No remote 'origin' found for this repository."
        case .prCreationFailed(let r):  return "PR creation failed: \(r)"
        }
    }
}

final class PRService {
    // TODO: [Phase 6] Implement.
    // Primary: run `gh pr create` via ProcessRunner.
    // Fallback: open https://github.com/<owner>/<repo>/compare/<branch>?expand=1 in browser.

    /// Creates a PR and returns the PR URL.
    func createPR(
        repoPath: String,
        branch: String,
        title: String,
        body: String
    ) async throws -> String {
        // TODO
        return ""
    }
}
