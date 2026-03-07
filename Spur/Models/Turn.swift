import Foundation

struct Turn: Codable, Identifiable {
    let id: UUID
    var number: Int
    var label: String
    /// HEAD commit hash when the Turn was started.
    var startCommit: String
    /// HEAD commit hash after "Capture Checkpoint"; nil until captured.
    var endCommit: String?
    /// All commit hashes between startCommit (exclusive) and endCommit (inclusive).
    var commitRange: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        number: Int,
        label: String,
        startCommit: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.number = number
        self.label = label
        self.startCommit = startCommit
        self.endCommit = nil
        self.commitRange = []
        self.createdAt = createdAt
    }
}
