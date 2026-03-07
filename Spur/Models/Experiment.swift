import Foundation

struct Experiment: Codable, Identifiable {
    let id: UUID
    var name: String
    var slug: String
    var createdAt: Date
    var optionIds: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        slug: String,
        createdAt: Date = Date(),
        optionIds: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.createdAt = createdAt
        self.optionIds = optionIds
    }
}
