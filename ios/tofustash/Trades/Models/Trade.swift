import Foundation

// A trade record — represents either a habit completion that earned tofu or a
// reward purchase that spent tofu.
// Like the Habit struct, this is a value type (struct) — immutable, copied
// on assignment. Think of it like a frozen object in JS.
//
// Protocol conformances (like implementing interfaces in TS):
// - Identifiable: has an `id` property, used by SwiftUI List/ForEach for diffing
// - Equatable: supports `==` comparison (auto-synthesized for structs)
// - Sendable: safe to pass across threads
struct Trade: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let id: RecordID
    let taskId: RecordID?
    let habitId: RecordID?
    let rewardId: RecordID?
    let amount: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}
