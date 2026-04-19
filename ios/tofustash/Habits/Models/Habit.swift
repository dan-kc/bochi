import Foundation

// A habit — the core data model. This is a struct (value type), meaning it's
// copied on assignment rather than shared by reference. Think of it like an
// immutable object in JS — to "change" it you create a new copy with spread:
// `{ ...habit, name: "new" }`. In Swift you'd use `Habit(id: habit.id, name: "new", ...)`.
//
// Protocol conformances (after the colon) are like implementing interfaces in TS:
// - Identifiable: requires an `id` property. SwiftUI's List/ForEach use this
//   to diff items efficiently (like React's `key` prop, but automatic).
// - Equatable: lets you use `==` to compare two Habits (auto-synthesized for structs).
// - Sendable: marks this type as safe to pass across threads (like Rust's Send trait).
struct Habit: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let id: RecordID            // Canonical UUID wrapper — unique identifier
    let name: String            // 1-100 chars, required
    let description: String     // optional text — empty string means "not set"
    let createdAt: Date         // Swift uses Date (not ISO strings) for timestamps
    let updatedAt: Date
    let deletedAt: Date?        // Optional<Date> — nil means the habit is active.
                                // `?` suffix is syntactic sugar for Optional<T>,
                                // like `T | null` in TypeScript.
    let frequency: Double?      // times per day (e.g. 0.5 = every other day). nil = not set.
    let difficultyTier: HabitDifficultyTier?

    // Whether this habit has the required properties to calculate a reward price.
    // Both frequency and difficulty tier must be set for the reward formula to
    // produce meaningful results — without frequency, F is always 1 (no diminishing
    // returns), and without a difficulty tier the user has not classified the habit yet.
    var canTrade: Bool {
        frequency != nil && difficultyTier != nil
    }
}
