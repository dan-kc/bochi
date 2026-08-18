import Foundation

// A task-to-recurringTask prerequisite row. The baseline count freezes the recurringTask's
// completion total when the dependency is assigned, so "3 more" means three
// additional completions after that moment instead of three lifetime completions.
struct TaskRecurringTaskDependency: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let taskId: RecordID
    let recurringTaskId: RecordID
    let requiredCompletions: Int
    let baselineCompletionCount: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let serverRevision: Int64?

    var id: RecordID { RecordID("\(taskId):\(recurringTaskId)") }

    init(
        taskId: RecordID,
        recurringTaskId: RecordID,
        requiredCompletions: Int,
        baselineCompletionCount: Int,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        serverRevision: Int64? = nil
    ) {
        self.taskId = taskId
        self.recurringTaskId = recurringTaskId
        self.requiredCompletions = requiredCompletions
        self.baselineCompletionCount = baselineCompletionCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }
}
