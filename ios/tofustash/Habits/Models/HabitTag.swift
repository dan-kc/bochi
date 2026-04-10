import Foundation

// Junction model — represents the many-to-many relationship between
// Habit and Tag. Each record says "this tag is applied to this habit."
//
// In React/TS you might model this as an array of tagIds on the habit object,
// but a separate junction model allows:
// - Independent soft-delete (remove a tag from a habit without deleting the tag)
// - Timestamps for when the association was created/modified
// - Sync with the backend's `habit_tags` junction table
struct HabitTag: Identifiable, Equatable, Sendable {
    let id: String              // UUID string — unique per association
    let habitId: String         // FK → Habit.id
    let tagId: String           // FK → Tag.id
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?        // nil = active, non-nil = soft-deleted
}
