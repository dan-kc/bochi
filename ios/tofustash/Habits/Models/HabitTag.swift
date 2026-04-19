import Foundation

// Junction model — represents the many-to-many relationship between
// Habit and Tag. Each record says "this tag is applied to this habit."
//
// In React/TS you might model this as an array of tagIds on the habit object,
// but a separate junction model allows:
// - Independent soft-delete (remove a tag from a habit without deleting the tag)
// - Timestamps for when the association was created/modified
// - Sync with the backend's `habit_tags` junction table
struct HabitTag: Identifiable, Equatable, Sendable, Codable {
    let habitId: RecordID       // FK → Habit.id
    let tagId: RecordID         // FK → Tag.id
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?        // nil = active, non-nil = soft-deleted

    // The backend identifies habit-tag rows by the `(habitId, tagId)` pair.
    // Using a computed ID keeps SwiftUI's `Identifiable` support without adding
    // a second local-only identifier that sync would need to ignore.
    var id: RecordID { RecordID("\(habitId):\(tagId)") }
}
