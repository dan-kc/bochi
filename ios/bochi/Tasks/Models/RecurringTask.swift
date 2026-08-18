import Foundation

// A recurringTask — the core data model. This is a struct (value type), meaning it's
// copied on assignment rather than shared by reference. Think of it like an
// immutable object in JS — to "change" it you create a new copy with spread:
// `{ ...recurringTask, name: "new" }`. In Swift you'd use `RecurringTask(id: recurringTask.id, name: "new", ...)`.
//
// Protocol conformances (after the colon) are like implementing interfaces in TS:
// - Identifiable: requires an `id` property. SwiftUI's List/ForEach use this
//   to diff items efficiently (like React's `key` prop, but automatic).
// - Equatable: lets you use `==` to compare two RecurringTasks (auto-synthesized for structs).
// - Sendable: marks this type as safe to pass across threads (like Rust's Send trait).
nonisolated struct RecurringTask: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let id: RecordID            // Canonical UUID wrapper — unique identifier
    let name: String            // 1-100 chars, required
    let description: String     // optional text — empty string means "not set"
    let createdAt: Date         // Swift uses Date (not ISO strings) for timestamps
    let updatedAt: Date
    let deletedAt: Date?        // Optional<Date> — nil means the recurringTask is active.
                                // `?` suffix is syntactic sugar for Optional<T>,
                                // like `T | null` in TypeScript.
    let frequency: Double?      // times per day (e.g. 0.5 = every other day). nil = not set.
    let lockoutDurationSeconds: Int?
    let basePrice: Int
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
        frequency: Double?,
        lockoutDurationSeconds: Int? = nil,
        basePrice: Int = 100,
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
        self.frequency = frequency
        self.lockoutDurationSeconds = lockoutDurationSeconds
        self.basePrice = basePrice
        self.pinned = pinned
        self.hidden = hidden
        self.timerSelection = timerSelection
        self.serverRevision = serverRevision
    }

    // Claiming is no longer blocked by missing pricing fields. Optional inputs
    // fall back to the cheapest reward calculation instead, so users can still
    // claim immediately and improve pricing later by filling in more detail.
    var canTrade: Bool {
        deletedAt == nil
    }
}
