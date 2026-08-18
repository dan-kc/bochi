import Foundation

// Reward is the inverse of RecurringTask: instead of earning points for doing something,
// the user spends points to buy something tempting. The recurring frequency cap
// can raise the live price above the user-entered base price.
// - `maxFrequency` is the maximum healthy purchase rate the user wants
nonisolated struct Reward: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let id: RecordID
    let recurring: Bool
    let name: String
    let description: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let maxFrequency: Double?
    let lockoutDurationSeconds: Int?
    let basePrice: Int
    let pinned: Bool
    let hidden: Bool
    let timerSelection: EntityTimerSelection
    let serverRevision: Int64?

    init(
        id: RecordID,
        recurring: Bool = true,
        name: String,
        description: String,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        maxFrequency: Double?,
        lockoutDurationSeconds: Int? = nil,
        basePrice: Int = 500,
        pinned: Bool = false,
        hidden: Bool = false,
        timerSelection: EntityTimerSelection = .none,
        serverRevision: Int64? = nil
    ) {
        self.id = id
        self.recurring = recurring
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.maxFrequency = maxFrequency
        self.lockoutDurationSeconds = lockoutDurationSeconds
        self.basePrice = basePrice
        self.pinned = pinned
        self.hidden = hidden
        self.timerSelection = timerSelection
        self.serverRevision = serverRevision
    }

    // Buying is allowed even when optional pricing fields are blank. The
    // calculator now uses the most expensive fallback values by default so
    // filling in more detail can only improve the price.
    var canPurchase: Bool {
        deletedAt == nil
    }
}
