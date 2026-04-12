import Foundation

// @Observable is a macro that makes all stored properties automatically trigger
// SwiftUI view updates when they change. It's like a Zustand store with built-in
// fine-grained reactivity — SwiftUI tracks which properties each view reads and
// only re-renders views that depend on properties that actually changed.
// Unlike React's useState where you must call a setter, here you just mutate
// the property directly and SwiftUI picks up the change automatically.
//
// @MainActor ensures all access happens on the main thread — like ensuring
// state updates only happen during React's render cycle. This prevents race
// conditions when multiple threads try to modify habits simultaneously.
//
// `final` means this class can't be subclassed (like a sealed class in Kotlin,
// or not exporting a base class in TS). This lets the compiler optimize.
@Observable
@MainActor
final class HabitStore {

    // `private(set)` means external code can read `habits` but only this class
    // can write to it. Like a readonly property in TS with a private setter.
    // Views can read `habits` to display them, but must go through methods to modify.
    private(set) var habits: [Habit] = []

    // Computed property — recalculated every time it's accessed, like a getter
    // in a JS class or a derived value in a Zustand store. SwiftUI is smart enough
    // to track dependencies through computed properties, so views using `activeHabits`
    // will re-render when `habits` changes (but only if the filtered result differs).
    var activeHabits: [Habit] {
        // .filter {} is exactly like Array.filter() in JS.
        // `$0` is shorthand for the first closure parameter — like an implicit
        // arrow function parameter. `{ $0.deletedAt == nil }` is like
        // `.filter(h => h.deletedAt === null)` in JS.
        habits.filter { $0.deletedAt == nil }
    }

    // Creates a new habit and appends it to the store.
    // Returns the created Habit, or nil if validation fails (name empty or too long).
    //
    // Default parameter values work just like in JS/TS — callers can omit them:
    //   store.addHabit(name: "Exercise")
    //   store.addHabit(name: "Exercise", description: "Gym", frequency: 1.0)
    //
    // `@discardableResult` suppresses the compiler warning when the caller ignores
    // the return value. Without it, `store.addHabit(name: "x")` (no `let _ =`)
    // would produce a warning. There's no JS equivalent — JS never warns about
    // unused return values.
    @discardableResult
    func addHabit(id: String? = nil, name: String, description: String = "", frequency: Double? = nil, difficultyRank: String? = nil) -> Habit? {
        // .trimmingCharacters(in: .whitespaces) is like .trim() in JS.
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        // `guard` is an early-return check — like `if (!condition) return` in JS,
        // but the compiler enforces that the else branch must exit the scope
        // (return, throw, break, etc). This prevents accidentally continuing
        // with invalid data.
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else {
            return nil
        }

        let now = Date() // Date() with no args = current time, like `new Date()` in JS

        let habit = Habit(
            // Use the provided ID (for tag associations) or generate a new one.
            // Similar to crypto.randomUUID() in JS.
            id: id ?? UUID().uuidString,
            name: trimmedName,
            description: description,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            frequency: frequency,
            difficultyRank: difficultyRank
        )

        // .append() is like .push() in JS — adds to the end of the array.
        // Because `habits` is an @Observable property, SwiftUI will automatically
        // detect this mutation and re-render any views reading `habits` or `activeHabits`.
        habits.append(habit)
        return habit
    }

    // Soft-deletes a habit by setting its `deletedAt` timestamp.
    // The habit stays in `habits` but is excluded from `activeHabits`.
    // If the ID doesn't match any habit, this is a no-op (no crash).
    func deleteHabit(id: String) {
        // .firstIndex(where:) is like .findIndex() in JS — returns the index
        // of the first match, or nil if not found.
        guard let index = habits.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existing = habits[index]

        // Since Habit is a struct (value type, immutable), we can't just set
        // `existing.deletedAt = Date()`. Instead we create a new Habit with
        // the updated field — like spread-copying in JS:
        //   const updated = { ...existing, deletedAt: new Date() }
        habits[index] = Habit(
            id: existing.id,
            name: existing.name,
            description: existing.description,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            deletedAt: Date(),
            frequency: existing.frequency,
            difficultyRank: existing.difficultyRank
        )
    }

    // Updates an existing habit's fields. Only fields with non-nil values are
    // changed — pass nil (the default) to leave a field unchanged.
    //
    // The `Double??` and `String??` types use Swift's nested Optional pattern:
    //   - `.none` (outer nil) → "don't change this field"
    //   - `.some(nil)` → "clear this field (set to nil)"
    //   - `.some(.some(value))` → "set this field to value"
    //
    // In JavaScript, this maps to:
    //   - `undefined` → don't change
    //   - `null` → clear
    //   - `value` → set
    // But JS conflates undefined/null in most APIs. Swift's type system makes
    // the three states explicit and enforced at compile time.
    func updateHabit(
        id: String,
        name: String? = nil,
        description: String? = nil,
        frequency: Double?? = nil,
        difficultyRank: String?? = nil
    ) {
        guard let index = habits.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existing = habits[index]

        // For each field: if the parameter is nil (outer), keep existing value.
        // Otherwise unwrap one level to get the new value (which may itself be nil).
        // Determine the new name: if a valid name was provided, use it.
        // If the provided name is invalid (empty or too long), fall through
        // and keep the existing name — don't reject the entire update.
        // This is important for auto-save: the user may temporarily have an
        // empty name field while editing other fields like frequency or tags.
        let newName: String
        if let name = name {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && trimmed.count <= 100 {
                newName = trimmed
            } else {
                newName = existing.name
            }
        } else {
            newName = existing.name
        }

        habits[index] = Habit(
            id: existing.id,
            name: newName,
            description: description ?? existing.description,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            deletedAt: existing.deletedAt,
            // `frequency ?? existing.frequency` — if outer Optional is nil, keep existing.
            // If outer is .some, unwrap to get the inner Optional<Double>.
            frequency: frequency ?? existing.frequency,
            difficultyRank: difficultyRank ?? existing.difficultyRank
        )
    }
}
