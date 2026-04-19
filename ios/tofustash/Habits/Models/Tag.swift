import Foundation

// A tag that can be applied to habits. Tags have a name and a color for
// visual distinction. Like Habit, this is a value-type struct — immutable
// once created, you "update" it by creating a new copy with changed fields.
//
// In React/TS this would be a plain interface:
//   interface Tag { id: string; name: string; colorHex: string; ... }
struct Tag: Identifiable, Equatable, Sendable, Codable {
    let id: RecordID            // Canonical UUID wrapper
    let name: String            // Tag display name
    let colorHex: String        // "#RRGGBB" hex color for the tag pill
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?        // nil = active, non-nil = soft-deleted
}
