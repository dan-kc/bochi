import Foundation

// A reward-to-recurringTask prerequisite row. The baseline is reset after buying the
// reward so the user must earn the same recurringTask completions again next time.
struct RewardRecurringTaskDependency: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let rewardId: RecordID
    let recurringTaskId: RecordID
    let requiredCompletions: Int
    let baselineCompletionCount: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let serverRevision: Int64?

    var id: RecordID { RecordID("\(rewardId):\(recurringTaskId)") }

    init(
        rewardId: RecordID,
        recurringTaskId: RecordID,
        requiredCompletions: Int,
        baselineCompletionCount: Int,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        serverRevision: Int64? = nil
    ) {
        self.rewardId = rewardId
        self.recurringTaskId = recurringTaskId
        self.requiredCompletions = requiredCompletions
        self.baselineCompletionCount = baselineCompletionCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }
}
