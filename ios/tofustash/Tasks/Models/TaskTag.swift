import Foundation

// Junction row between a task and a shared tag.
struct TaskTag: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let taskId: RecordID
    let tagId: RecordID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    var id: RecordID { RecordID("\(taskId):\(tagId)") }
}
