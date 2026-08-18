import Foundation
import Testing
@testable import bochi

@MainActor
struct RecurringTaskStoreTests {
    private func makeSUT() -> RecurringTaskStore {
        RecurringTaskStore(storageURL: TestHelpers.makeTemporaryFileURL("recurringTasks"))
    }

    // Behaviour: When the app first loads with no data, the recurringTask list is empty.
    @Test func initialStoreHasNoRecurringTasks() {
        let sut = makeSUT()

        #expect(sut.recurringTasks.isEmpty)
        #expect(sut.activeRecurringTasks.isEmpty)
    }

    // Behaviour: When a user creates a new recurringTask, it appears in their recurringTask list.
    @Test func addRecurringTaskAppendsToRecurringTasks() {
        let sut = makeSUT()

        let recurringTask = sut.addRecurringTask(name: "Exercise")

        #expect(sut.recurringTasks.count == 1)
        #expect(recurringTask?.name == "Exercise")
    }

    // Behaviour: When a user creates a recurringTask with all remaining pricing and
    // cadence fields, those fields are saved correctly.
    @Test func addRecurringTaskWithAllFields() {
        let sut = makeSUT()

        let recurringTask = sut.addRecurringTask(
            name: "Exercise",
            description: "Daily workout",
            frequency: 1.0,
            lockoutDurationSeconds: 3_600,
            basePrice: 125
        )

        #expect(recurringTask?.name == "Exercise")
        #expect(recurringTask?.description == "Daily workout")
        #expect(recurringTask?.frequency == 1.0)
        #expect(recurringTask?.lockoutDurationSeconds == 3_600)
        #expect(recurringTask?.basePrice == 125)
    }

    // Behaviour: a saved recurringTask base price should survive app restart and remain
    // editable without any removed permanent adjustment field.
    @Test func recurringTaskBasePriceSavesLoadsAndUpdates() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("recurringTask-base-price-persistence")
        let sut = RecurringTaskStore(storageURL: storageURL)
        let recurringTask = try #require(sut.addRecurringTask(name: "Exercise", basePrice: 180))

        #expect(sut.recurringTasks.first?.basePrice == 180)

        let reloaded = RecurringTaskStore(storageURL: storageURL)
        #expect(reloaded.recurringTasks.first?.basePrice == 180)

        reloaded.updateRecurringTask(id: recurringTask.id, basePrice: 90)

        #expect(reloaded.recurringTasks.first?.basePrice == 90)
    }

    // Behaviour: When a user types a recurringTask name with leading/trailing spaces,
    // the name is cleaned up automatically on save.
    @Test func addRecurringTaskTrimsWhitespace() {
        let sut = makeSUT()

        let recurringTask = sut.addRecurringTask(name: "  My RecurringTask  ")

        #expect(recurringTask?.name == "My RecurringTask")
    }

    // Behaviour: When a user tries to save a recurringTask with no name, it is not created.
    @Test func addRecurringTaskWithEmptyNameReturnsNil() {
        let sut = makeSUT()

        #expect(sut.addRecurringTask(name: "") == nil)
        #expect(sut.addRecurringTask(name: "   ") == nil)
        #expect(sut.recurringTasks.isEmpty)
    }

    // Behaviour: When a user tries to save a recurringTask with a name longer than 100
    // characters, the recurringTask is not created.
    @Test func addRecurringTaskWithNameOver100CharsReturnsNil() {
        let sut = makeSUT()

        let longName = String(repeating: "a", count: 101)
        let recurringTask = sut.addRecurringTask(name: longName)

        #expect(recurringTask == nil)
        #expect(sut.recurringTasks.isEmpty)
    }

    // Behaviour: When a user deletes a recurringTask, it is soft-deleted and removed
    // from the visible active list.
    @Test func deleteRecurringTaskSetsDeletedAt() {
        let sut = makeSUT()
        let recurringTask = sut.addRecurringTask(name: "Exercise")!

        sut.deleteRecurringTask(id: recurringTask.id)

        let deleted = sut.recurringTasks.first(where: { $0.id == recurringTask.id })
        #expect(deleted?.deletedAt != nil)
        #expect(sut.activeRecurringTasks.isEmpty)
    }

    // Behaviour: pinning a recurringTask should survive a store reload so its list
    // priority is not lost when the app restarts.
    @Test func pinRecurringTaskPersists() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("recurringTask-pin-persistence")
        let sut = RecurringTaskStore(storageURL: storageURL)
        let recurringTask = try #require(sut.addRecurringTask(name: "Exercise"))

        sut.setPinned(id: recurringTask.id, pinned: true)

        #expect(sut.recurringTasks.first?.pinned == true)
        let reloaded = RecurringTaskStore(storageURL: storageURL)
        #expect(reloaded.recurringTasks.first?.pinned == true)
    }

    // Behaviour: hiding a recurringTask should persist for sync without removing it
    // from the current list while the UI hiding rules are still pending.
    @Test func hideRecurringTaskPersistsWithoutFiltering() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("recurringTask-hidden-persistence")
        let sut = RecurringTaskStore(storageURL: storageURL)
        let recurringTask = try #require(sut.addRecurringTask(name: "Exercise"))

        sut.setHidden(id: recurringTask.id, hidden: true)

        #expect(sut.recurringTasks.first?.hidden == true)
        #expect(sut.activeRecurringTasks.first?.hidden == true)
        let reloaded = RecurringTaskStore(storageURL: storageURL)
        #expect(reloaded.recurringTasks.first?.hidden == true)
    }

    // Behaviour: When a user renames a recurringTask, the new name is saved.
    @Test func updateRecurringTaskChangesName() {
        let sut = makeSUT()
        let recurringTask = sut.addRecurringTask(name: "Exercise")!

        sut.updateRecurringTask(id: recurringTask.id, name: "Workout")

        #expect(sut.recurringTasks.first?.name == "Workout")
    }

    // Behaviour: When a user only changes one field, all other fields remain untouched.
    @Test func updateRecurringTaskPreservesUnchangedFields() {
        let sut = makeSUT()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let recurringTask = sut.addRecurringTask(
            name: "Exercise",
            description: "Daily",
            frequency: 1.0,
            lockoutDurationSeconds: 1_800,
            basePrice: 140,
            createdAt: createdAt,
            updatedAt: createdAt
        )!

        sut.updateRecurringTask(id: recurringTask.id, name: "Workout")

        let updated = sut.recurringTasks.first!
        #expect(updated.name == "Workout")
        #expect(updated.description == "Daily")
        #expect(updated.frequency == 1.0)
        #expect(updated.lockoutDurationSeconds == 1_800)
        #expect(updated.basePrice == 140)
        #expect(updated.createdAt == recurringTask.createdAt)
    }

    // Behaviour: When a user edits lockout and base price, those values should
    // persist with the recurringTask.
    @Test func updateRecurringTaskChangesLockoutAndBasePrice() {
        let sut = makeSUT()
        let recurringTask = sut.addRecurringTask(name: "Exercise")!

        sut.updateRecurringTask(
            id: recurringTask.id,
            lockoutDurationSeconds: .some(7_200),
            basePrice: 225
        )

        let updated = sut.recurringTasks.first!
        #expect(updated.lockoutDurationSeconds == 7_200)
        #expect(updated.basePrice == 225)
    }

    // Behaviour: During auto-save, if the name field is temporarily empty,
    // other field changes still save and the existing name is preserved.
    @Test func updateWithEmptyNameStillUpdatesFrequency() {
        let sut = makeSUT()
        let recurringTask = sut.addRecurringTask(name: "Exercise", frequency: 1.0)!

        sut.updateRecurringTask(id: recurringTask.id, name: "", frequency: .some(2.0))

        let updated = sut.recurringTasks.first!
        #expect(updated.name == "Exercise")
        #expect(updated.frequency == 2.0)
    }

    // Behaviour: When a user creates a recurringTask with tags already selected, the recurringTask
    // is saved with the same ID that the tags were pre-associated with.
    @Test func addRecurringTaskWithProvidedIdUsesIt() {
        let sut = makeSUT()
        let preGeneratedId = RecordID("my-custom-id-123")

        let recurringTask = sut.addRecurringTask(id: preGeneratedId, name: "Exercise")

        #expect(recurringTask?.id == preGeneratedId)
    }

    // Behaviour: A signed-out user's local recurringTasks survive relaunch because the
    // iOS app persists the local-only store to disk.
    @Test func localRecurringTaskPersistsAcrossStoreRelaunch() {
        let fileURL = TestHelpers.makeTemporaryFileURL("persisted-recurringTasks")
        let firstStore = RecurringTaskStore(storageURL: fileURL)

        _ = firstStore.addRecurringTask(name: "Persist Me")

        let relaunchedStore = RecurringTaskStore(storageURL: fileURL)

        #expect(relaunchedStore.activeRecurringTasks.count == 1)
        #expect(relaunchedStore.activeRecurringTasks.first?.name == "Persist Me")
    }
}
