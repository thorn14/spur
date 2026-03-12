import Foundation

/// Top-level persisted state for a single repository.
/// Stored at ~/.spur/<repoId>.json
struct AppState: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var repoId: UUID
    var repoPath: String
    var baseBranch: String
    var installCommand: String
    var devCommand: String
    var prototypes: [Prototype]
    var options: [SpurOption]

    /// True when the repo has not yet been configured with install/dev commands.
    var needsSetup: Bool { installCommand.isEmpty || devCommand.isEmpty }

    init(repo: Repo) {
        self.schemaVersion = AppState.currentSchemaVersion
        self.repoId = repo.id
        self.repoPath = repo.path
        self.baseBranch = repo.baseBranch
        self.installCommand = repo.installCommand
        self.devCommand = repo.devCommand
        self.prototypes = []
        self.options = []
    }
}
