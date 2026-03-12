import Foundation

// "Option" is a reserved word in Swift, so we use SpurOption as the type name
// but expose the public-facing name via a typealias for clarity in the codebase.
// Using the full name "SpurOption" avoids confusion with Swift's Optional.
struct SpurOption: Codable, Identifiable {
    let id: UUID
    var prototypeId: UUID
    var name: String
    var slug: String
    /// Full branch name, e.g. "exp/color-study/warm-palette"
    var branchName: String
    /// Absolute path to the git worktree directory.
    var worktreePath: String
    var port: Int
    var status: OptionStatus
    /// Shell command used to start the dev server for this option.
    var devCommand: String
    /// Commit hash this Option was forked from; nil if branched from main.
    var forkedFromCommit: String?
    var prURL: String?
    var prNumber: Int?
    var turns: [Turn]

    init(
        id: UUID = UUID(),
        prototypeId: UUID,
        name: String,
        slug: String,
        branchName: String,
        worktreePath: String,
        port: Int
    ) {
        self.id = id
        self.prototypeId = prototypeId
        self.name = name
        self.slug = slug
        self.branchName = branchName
        self.worktreePath = worktreePath
        self.port = port
        self.status = .idle
        self.devCommand = Constants.defaultDevCommand
        self.forkedFromCommit = nil
        self.prURL = nil
        self.prNumber = nil
        self.turns = []
    }
}

enum OptionStatus: String, Codable {
    /// Worktree exists; dev server is not running.
    case idle
    /// Dev server is running.
    case running
    /// Worktree is missing from disk (reconciliation needed).
    case detached
    /// A git or process operation failed.
    case error
}
