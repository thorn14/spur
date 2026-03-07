import Foundation

/// Top-level persisted state for a single repository.
/// Stored at ~/.spur/<repoId>.json
struct AppState: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var repoId: UUID
    var repoPath: String
    var baseBranch: String
    var devCommand: String
    var experiments: [Experiment]
    var options: [SpurOption]

    init(repo: Repo) {
        self.schemaVersion = AppState.currentSchemaVersion
        self.repoId = repo.id
        self.repoPath = repo.path
        self.baseBranch = repo.baseBranch
        self.devCommand = repo.devCommand
        self.experiments = []
        self.options = []
    }
}
