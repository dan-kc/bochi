import Foundation

// A one-shot task. Unlike habits, tasks do not have cadence pricing or lockout;
// they become complete once claimed and stay in history until edited or deleted.
struct TaskItem: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let id: RecordID
    let name: String
    let description: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let completedAt: Date?
    let difficultyTier: HabitDifficultyTier?
    let durationSeconds: Int?
    let commitment: Int?
    let dueDate: Date?

    var canTrade: Bool {
        deletedAt == nil && completedAt == nil
    }
}
