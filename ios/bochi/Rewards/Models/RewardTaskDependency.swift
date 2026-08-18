import Foundation

// A reward-to-task prerequisite row. A refunded task completion makes this
// dependency incomplete again because the reward checks active task trades.
struct RewardTaskDependency: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let rewardId: RecordID
    let dependsOnTaskId: RecordID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let serverRevision: Int64?

    var id: RecordID { RecordID("\(rewardId):\(dependsOnTaskId)") }

    init(
        rewardId: RecordID,
        dependsOnTaskId: RecordID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        serverRevision: Int64? = nil
    ) {
        self.rewardId = rewardId
        self.dependsOnTaskId = dependsOnTaskId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }
}
