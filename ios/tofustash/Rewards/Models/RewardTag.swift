import Foundation

// Junction model for the many-to-many Reward ↔ Tag relationship.
// Keeping reward links separate from habit links means the global tag catalog
// stays shared while each feature owns its own association history.
struct RewardTag: Identifiable, Equatable, Sendable, Codable {
    let rewardId: RecordID
    let tagId: RecordID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    var id: RecordID { RecordID("\(rewardId):\(tagId)") }
}
