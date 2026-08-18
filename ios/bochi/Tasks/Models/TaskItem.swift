import Foundation

// A one-shot task. Completion is not stored on the task row; the app derives it
// from the user's task trade history so refunds can reopen the task naturally.
nonisolated struct TaskItem: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let id: RecordID
    let name: String
    let description: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let basePrice: Int
    let dueDate: Date?
    let pinned: Bool
    let hidden: Bool
    let timerSelection: EntityTimerSelection
    let serverRevision: Int64?

    init(
        id: RecordID,
        name: String,
        description: String,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        basePrice: Int = 200,
        dueDate: Date?,
        pinned: Bool = false,
        hidden: Bool = false,
        timerSelection: EntityTimerSelection = .none,
        serverRevision: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.basePrice = basePrice
        self.dueDate = dueDate
        self.pinned = pinned
        self.hidden = hidden
        self.timerSelection = timerSelection
        self.serverRevision = serverRevision
    }

    var canTrade: Bool {
        deletedAt == nil
    }
}
