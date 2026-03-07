import Foundation

struct Repo: Codable, Identifiable {
    let id: UUID
    var path: String
    var baseBranch: String
    var devCommand: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        path: String,
        baseBranch: String = Constants.defaultBaseBranch,
        devCommand: String = Constants.defaultDevCommand,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.baseBranch = baseBranch
        self.devCommand = devCommand
        self.createdAt = createdAt
    }
}
