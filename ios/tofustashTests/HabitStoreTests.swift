import Foundation
import Testing
@testable import tofustash

// @MainActor pins all tests to the main thread — needed because HabitStore
// uses @MainActor (like AuthManager). Without this, Swift's concurrency checker
// would prevent accessing main-actor-isolated properties from a background thread.
// In React terms: ensures everything runs on the "render thread."
@MainActor
struct HabitStoreTests {

    // SUT = "System Under Test". Factory method that returns a fresh store for each test.
    // Same pattern as AuthManagerTests.makeSUT() — keeps tests isolated from each other
    // (like creating a new component instance in each React test).
    private func makeSUT() -> HabitStore {
        return HabitStore()
    }

    // MARK: - Initial State
    // `MARK` comments create section headers in Xcode's jump bar (the breadcrumb nav).
    // No equivalent in React — it's like a code region / folder in VS Code's outline.

    @Test func initialStoreHasNoHabits() {
        let sut = makeSUT()

        // #expect() is Swift Testing's assertion — like Jest's expect().toBe()
        #expect(sut.habits.isEmpty)
        #expect(sut.activeHabits.isEmpty)
    }

    // MARK: - Adding Habits

    @Test func addHabitAppendsToHabits() {
        let sut = makeSUT()

        // `let` declares an immutable binding (like `const` in JS).
        // The return type is `Habit?` (Optional) — nil means validation failed.
        let habit = sut.addHabit(name: "Exercise")

        #expect(sut.habits.count == 1)
        // `habit != nil` checks the Optional contains a value — like `habit !== null` in TS.
        #expect(habit != nil)
        #expect(habit?.name == "Exercise")
    }

    @Test func addHabitGeneratesUniqueIds() {
        let sut = makeSUT()

        let habit1 = sut.addHabit(name: "Exercise")
        let habit2 = sut.addHabit(name: "Read")

        // Force-unwrap with `!` — crashes if nil. Safe in tests because we just
        // created these habits. In production code, always use `if let` or `guard let`.
        #expect(habit1!.id != habit2!.id)
    }

    @Test func addHabitWithAllFields() {
        let sut = makeSUT()

        let habit = sut.addHabit(name: "Exercise", description: "Daily workout", frequency: 1.0)

        #expect(habit?.name == "Exercise")
        #expect(habit?.description == "Daily workout")
        #expect(habit?.frequency == 1.0)
    }

    @Test func addHabitTrimsWhitespace() {
        let sut = makeSUT()

        let habit = sut.addHabit(name: "  My Habit  ")

        // .trimmingCharacters(in:) is like JS's .trim() but more configurable.
        // We expect the store to trim whitespace on save — not just for validation.
        #expect(habit?.name == "My Habit")
    }

    // MARK: - Validation

    @Test func addHabitWithEmptyNameReturnsNil() {
        let sut = makeSUT()

        // Empty string — should be rejected
        let habit1 = sut.addHabit(name: "")
        #expect(habit1 == nil)
        #expect(sut.habits.isEmpty)

        // Whitespace-only — should also be rejected (trimmed to empty)
        let habit2 = sut.addHabit(name: "   ")
        #expect(habit2 == nil)
        #expect(sut.habits.isEmpty)
    }

    @Test func addHabitWithNameOver100CharsReturnsNil() {
        let sut = makeSUT()

        // String(repeating:count:) creates a string by repeating a character —
        // like "a".repeat(101) in JS.
        let longName = String(repeating: "a", count: 101)
        let habit = sut.addHabit(name: longName)

        #expect(habit == nil)
        #expect(sut.habits.isEmpty)
    }

    // MARK: - Soft Delete

    @Test func deleteHabitSetsDeletedAt() {
        let sut = makeSUT()
        let habit = sut.addHabit(name: "Exercise")!

        sut.deleteHabit(id: habit.id)

        // Access the habit from the habits array (not activeHabits, which filters deleted).
        // .first(where:) is like JS's .find() — returns the first match or nil.
        let deleted = sut.habits.first(where: { $0.id == habit.id })
        #expect(deleted?.deletedAt != nil)
    }

    @Test func deletedHabitExcludedFromActiveHabits() {
        let sut = makeSUT()
        let habit1 = sut.addHabit(name: "Exercise")!
        _ = sut.addHabit(name: "Read")

        sut.deleteHabit(id: habit1.id)

        // activeHabits is a computed property that filters out deleted habits —
        // like a useMemo that derives from the habits array.
        #expect(sut.activeHabits.count == 1)
        #expect(sut.activeHabits.first?.name == "Read")
    }

    @Test func deleteNonexistentHabitIsNoOp() {
        let sut = makeSUT()
        _ = sut.addHabit(name: "Exercise")

        sut.deleteHabit(id: "nonexistent-id")

        #expect(sut.habits.count == 1)
        #expect(sut.activeHabits.count == 1)
    }

    // MARK: - Updating Habits

    @Test func updateHabitChangesName() {
        let sut = makeSUT()
        let habit = sut.addHabit(name: "Exercise")!

        sut.updateHabit(id: habit.id, name: "Workout")

        #expect(sut.habits.first?.name == "Workout")
    }

    @Test func updateHabitChangesDescription() {
        let sut = makeSUT()
        let habit = sut.addHabit(name: "Exercise")!

        sut.updateHabit(id: habit.id, description: "Daily workout")

        #expect(sut.habits.first?.description == "Daily workout")
    }

    @Test func updateHabitChangesFrequency() {
        let sut = makeSUT()
        let habit = sut.addHabit(name: "Exercise")!

        // .some(2.0) sets the frequency to 2.0
        sut.updateHabit(id: habit.id, frequency: .some(2.0))

        #expect(sut.habits.first?.frequency == 2.0)
    }

    @Test func updateHabitClearsFrequency() {
        let sut = makeSUT()
        let habit = sut.addHabit(name: "Exercise", frequency: 1.0)!

        // .some(nil) explicitly clears the frequency — like setting to null in JS
        sut.updateHabit(id: habit.id, frequency: .some(nil))

        #expect(sut.habits.first?.frequency == nil)
    }

    @Test func updateHabitPreservesUnchangedFields() {
        let sut = makeSUT()
        let habit = sut.addHabit(name: "Exercise", description: "Daily", frequency: 1.0, difficultyRank: "m")!

        // Only update the name — all other fields should stay the same
        sut.updateHabit(id: habit.id, name: "Workout")

        let updated = sut.habits.first!
        #expect(updated.name == "Workout")
        #expect(updated.description == "Daily")
        #expect(updated.frequency == 1.0)
        #expect(updated.difficultyRank == "m")
        #expect(updated.createdAt == habit.createdAt)
    }

    @Test func updateHabitTrimsName() {
        let sut = makeSUT()
        let habit = sut.addHabit(name: "Exercise")!

        sut.updateHabit(id: habit.id, name: "  Workout  ")

        #expect(sut.habits.first?.name == "Workout")
    }

    @Test func updateHabitWithEmptyNameIsNoOp() {
        let sut = makeSUT()
        let habit = sut.addHabit(name: "Exercise")!

        sut.updateHabit(id: habit.id, name: "")

        // Name should remain unchanged
        #expect(sut.habits.first?.name == "Exercise")
    }

    @Test func updateNonexistentHabitIsNoOp() {
        let sut = makeSUT()
        _ = sut.addHabit(name: "Exercise")

        sut.updateHabit(id: "nonexistent-id", name: "Workout")

        #expect(sut.habits.first?.name == "Exercise")
    }

    // MARK: - Invalid Name Should Not Block Other Fields

    // When the user is typing in the name field, it may temporarily be empty.
    // An invalid name should NOT prevent other field updates (frequency, description,
    // etc.) from saving — otherwise auto-save breaks when name is mid-edit.

    @Test func updateWithEmptyNameStillUpdatesFrequency() {
        let sut = makeSUT()
        let habit = sut.addHabit(name: "Exercise", frequency: 1.0)!

        // Pass an empty name alongside a frequency change — frequency should still save,
        // and the existing name should be preserved.
        sut.updateHabit(id: habit.id, name: "", frequency: .some(2.0))

        let updated = sut.habits.first!
        #expect(updated.name == "Exercise")
        #expect(updated.frequency == 2.0)
    }

    // MARK: - Adding with pre-generated ID

    // When creating a new habit, tags can be associated before the habit is saved
    // (using a pre-generated ID). The addHabit method must accept this ID so the
    // saved habit matches the tag associations. Like passing a UUID from a React
    // form's useState to the API call instead of letting the backend generate one.

    @Test func addHabitWithProvidedIdUsesIt() {
        let sut = makeSUT()
        let preGeneratedId = "my-custom-id-123"

        let habit = sut.addHabit(id: preGeneratedId, name: "Exercise")

        #expect(habit != nil)
        #expect(habit?.id == preGeneratedId)
    }

}
