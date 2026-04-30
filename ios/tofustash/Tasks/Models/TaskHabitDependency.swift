import Foundation

// A task-to-habit prerequisite row. The baseline count freezes the habit's
// completion total when the dependency is assigned, so "3 more" means three
// additional completions after that moment instead of three lifetime completions.
struct TaskHabitDependency: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let taskId: RecordID
    let habitId: RecordID
    let requiredCompletions: Int
    let baselineCompletionCount: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    var id: RecordID { RecordID("\(taskId):\(habitId)") }
}
