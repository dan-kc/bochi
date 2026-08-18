import Foundation

// A tag that can be applied to recurringTasks. Tags have a name and a color for
// visual distinction. Like RecurringTask, this is a value-type struct — immutable
// once created, you "update" it by creating a new copy with changed fields.
//
// In React/TS this would be a plain interface:
//   interface Tag { id: string; name: string; colorHex: string; ... }
nonisolated struct Tag: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let id: RecordID            // Canonical UUID wrapper
    let name: String            // Tag display name
    let colorHex: String        // "#RRGGBB" hex color for the tag pill
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?        // nil = active, non-nil = soft-deleted
    let serverRevision: Int64?

    init(
        id: RecordID,
        name: String,
        colorHex: String,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        serverRevision: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }
}
