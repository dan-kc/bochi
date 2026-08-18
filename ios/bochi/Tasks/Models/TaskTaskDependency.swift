import Foundation

// A task-to-task prerequisite row. Keeping dependencies as separate records
// lets the task itself stay immutable while dependency edits sync and soft-delete independently.
struct TaskTaskDependency: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let taskId: RecordID
    let dependsOnTaskId: RecordID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let serverRevision: Int64?

    var id: RecordID { RecordID("\(taskId):\(dependsOnTaskId)") }

    init(
        taskId: RecordID,
        dependsOnTaskId: RecordID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        serverRevision: Int64? = nil
    ) {
        self.taskId = taskId
        self.dependsOnTaskId = dependsOnTaskId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }
}
