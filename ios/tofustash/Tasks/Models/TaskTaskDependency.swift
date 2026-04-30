import Foundation

// A task-to-task prerequisite row. Keeping dependencies as separate records
// lets the task itself stay immutable while dependency edits sync and soft-delete independently.
struct TaskTaskDependency: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let taskId: RecordID
    let dependsOnTaskId: RecordID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    var id: RecordID { RecordID("\(taskId):\(dependsOnTaskId)") }
}
