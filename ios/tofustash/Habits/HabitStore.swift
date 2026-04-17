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

    // Creates a new habit from the add form. Returning nil means "do not save":
    // the UI keeps the form open because the entered name was not acceptable.
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
        // User-entered names are normalized on save so accidental spaces do not
        // create visually duplicate habits.
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
            // New-habit flows can pre-generate an ID so tags and other draft state
            // attach to the same record before the habit is finally saved.
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

    // Delete is implemented as a soft delete so the habit disappears from the
    // visible list immediately without losing the underlying record.
    func deleteHabit(id: String) {
        // .firstIndex(where:) is like .findIndex() in JS — returns the index
        // of the first match, or nil if not found.
        guard let index = habits.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existing = habits[index]

        // Habit is a struct, so updates create a replacement value rather than
        // mutating one shared object in place.
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

    // Updates an existing habit while preserving any fields the user did not
    // touch in the form.
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

        // Name validation is intentionally forgiving during edit mode. If the
        // user is mid-edit and the field is temporarily empty, auto-save still
        // persists other changes instead of breaking the entire draft.
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
            frequency: frequency ?? existing.frequency,
            difficultyRank: difficultyRank ?? existing.difficultyRank
        )
    }
}
