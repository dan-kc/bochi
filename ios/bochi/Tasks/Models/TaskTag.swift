import Foundation

// Junction row between a task and a shared tag.
struct TaskTag: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let taskId: RecordID
    let tagId: RecordID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let serverRevision: Int64?

    var id: RecordID { RecordID("\(taskId):\(tagId)") }

    init(
        taskId: RecordID,
        tagId: RecordID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        serverRevision: Int64? = nil
    ) {
        self.taskId = taskId
        self.tagId = tagId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }
}
