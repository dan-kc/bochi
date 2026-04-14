import Foundation

// A trade record — represents a single habit completion that earned tofu.
// Like the Habit struct, this is a value type (struct) — immutable, copied
// on assignment. Think of it like a frozen object in JS.
//
// Protocol conformances (like implementing interfaces in TS):
// - Identifiable: has an `id` property, used by SwiftUI List/ForEach for diffing
// - Equatable: supports `==` comparison (auto-synthesized for structs)
// - Sendable: safe to pass across threads
struct Trade: Identifiable, Equatable, Sendable {
    let id: String          // UUID string — unique identifier
    let habitId: String     // Which habit was completed
    let amount: Int         // Tofu earned (always positive for habit completions)
    let createdAt: Date     // When the trade was created
}
