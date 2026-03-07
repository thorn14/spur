import Foundation
import os

private let logger = Logger(subsystem: Constants.appSubsystem, category: "RepoViewModel")

@MainActor
final class RepoViewModel: ObservableObject {
    @Published var currentRepo: Repo?
    @Published var appState: AppState?
    @Published var isLoading = false
    @Published var error: Error?

    private let persistence: PersistenceService

    init(persistence: PersistenceService) {
        self.persistence = persistence
    }

    // MARK: - Repo Selection

    /// Validates the directory (requires .git + package.json), then persists and selects it.
    func selectRepo(path: String) async {
        isLoading = true
        defer { isLoading = false }

        guard validateRepoDirectory(path: path) else {
            error = RepoError.invalidDirectory(path)
            return
        }

        let repo = Repo(path: path)
        let state = AppState(repo: repo)
        do {
            try persistence.save(state)
            self.currentRepo = repo
            self.appState = state
            logger.info("Selected repo at \(path)")
        } catch {
            self.error = error
            logger.error("Failed to save repo: \(error.localizedDescription)")
        }
    }

    /// Loads the most recently saved repo on app launch.
    func loadLastRepo() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let ids = try persistence.listRepoIds()
            guard let lastId = ids.first else {
                logger.debug("No persisted repos found — showing repo picker.")
                return
            }
            let state = try persistence.load(repoId: lastId)
            self.appState = state
            self.currentRepo = Repo(
                id: state.repoId,
                path: state.repoPath,
                baseBranch: state.baseBranch,
                devCommand: state.devCommand
            )
            logger.info("Loaded last repo: \(state.repoPath)")
        } catch {
            // Not surfaced to user — first launch or corrupt state is handled by showing picker.
            logger.error("Failed to load last repo: \(error.localizedDescription)")
        }
    }

    /// Persists the current in-memory state to disk.
    func persistState() {
        guard let state = appState else { return }
        do {
            try persistence.save(state)
        } catch {
            self.error = error
            logger.error("Failed to persist state: \(error.localizedDescription)")
        }
    }

    // MARK: - Validation

    private func validateRepoDirectory(path: String) -> Bool {
        let fm = FileManager.default
        let gitPath = (path as NSString).appendingPathComponent(".git")
        let packagePath = (path as NSString).appendingPathComponent("package.json")
        return fm.fileExists(atPath: gitPath) && fm.fileExists(atPath: packagePath)
    }
}

// MARK: - Errors

enum RepoError: Error, LocalizedError {
    case invalidDirectory(String)

    var errorDescription: String? {
        switch self {
        case .invalidDirectory(let path):
            return "\(path) is not a valid repository. Make sure it contains .git and package.json."
        }
    }
}
