import Foundation

// Junction model — represents the many-to-many relationship between
// RecurringTask and Tag. Each record says "this tag is applied to this recurringTask."
//
// In React/TS you might model this as an array of tagIds on the recurringTask object,
// but a separate junction model allows:
// - Independent soft-delete (remove a tag from a recurringTask without deleting the tag)
// - Timestamps for when the association was created/modified
// - Sync with the backend's `recurring_task_tags` junction table
struct RecurringTaskTag: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let recurringTaskId: RecordID       // FK → RecurringTask.id
    let tagId: RecordID         // FK → Tag.id
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?        // nil = active, non-nil = soft-deleted
    let serverRevision: Int64?

    // The backend identifies recurringTask-tag rows by the `(recurringTaskId, tagId)` pair.
    // Using a computed ID keeps SwiftUI's `Identifiable` support without adding
    // a second local-only identifier that sync would need to ignore.
    var id: RecordID { RecordID("\(recurringTaskId):\(tagId)") }

    init(
        recurringTaskId: RecordID,
        tagId: RecordID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        serverRevision: Int64? = nil
    ) {
        self.recurringTaskId = recurringTaskId
        self.tagId = tagId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }
}
