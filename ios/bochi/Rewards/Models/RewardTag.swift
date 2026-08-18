import Foundation

// Junction model for the many-to-many Reward ↔ Tag relationship.
// Keeping reward links separate from recurringTask links means the global tag catalog
// stays shared while each feature owns its own association history.
struct RewardTag: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let rewardId: RecordID
    let tagId: RecordID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let serverRevision: Int64?

    var id: RecordID { RecordID("\(rewardId):\(tagId)") }

    init(
        rewardId: RecordID,
        tagId: RecordID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        serverRevision: Int64? = nil
    ) {
        self.rewardId = rewardId
        self.tagId = tagId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }
}
