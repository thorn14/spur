import Foundation

struct Repo: Codable, Identifiable {
    let id: UUID
    var path: String
    var baseBranch: String
    var installCommand: String
    var devCommand: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        path: String,
        baseBranch: String = Constants.defaultBaseBranch,
        installCommand: String = "",
        devCommand: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.baseBranch = baseBranch
        self.installCommand = installCommand
        self.devCommand = devCommand
        self.createdAt = createdAt
    }
}
