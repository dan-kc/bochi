import Foundation
import Testing
@testable import bochi

@MainActor
struct TaskStoreTests {
    private func makeSUT() -> TaskStore {
        TaskStore(storageURL: TestHelpers.makeTemporaryFileURL("tasks"))
    }

    // Behaviour: When the app first loads with no task data, the task list is empty.
    @Test func initialStoreHasNoTasks() {
        let sut = makeSUT()
        #expect(sut.tasks.isEmpty)
    }

    // Behaviour: Saving a task should persist its user-facing fields, including
    // the submitted price and due date.
    @Test func addTaskAppendsToTasks() {
        let sut = makeSUT()
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)

        let task = sut.addTask(
            name: "Submit report",
            description: "Finish the draft",
            basePrice: 275,
            dueDate: dueDate
        )

        #expect(sut.tasks.count == 1)
        #expect(task?.name == "Submit report")
        #expect(task?.basePrice == 275)
        #expect(task?.dueDate == dueDate)
    }

    // Behaviour: a saved task price should survive app restart and remain
    // editable without any removed permanent adjustment field.
    @Test func taskBasePriceSavesLoadsAndUpdates() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("task-base-price-persistence")
        let sut = TaskStore(storageURL: storageURL)
        let task = try #require(sut.addTask(name: "Submit report", basePrice: 250))

        #expect(sut.tasks.first?.basePrice == 250)

        let reloaded = TaskStore(storageURL: storageURL)
        #expect(reloaded.tasks.first?.basePrice == 250)

        reloaded.updateTask(id: task.id, basePrice: 125)

        #expect(reloaded.tasks.first?.basePrice == 125)
    }

    // Behaviour: task auto-save should keep the last valid name while still
    // persisting other edits when the user temporarily clears the name field.
    @Test func updateTaskWithEmptyNamePreservesExistingNameAndAppliesOtherFields() throws {
        let sut = makeSUT()
        let task = try #require(sut.addTask(name: "Book appointment"))
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)

        sut.updateTask(
            id: task.id,
            name: "",
            basePrice: 300,
            dueDate: .some(dueDate)
        )

        let updated = try #require(sut.tasks.first(where: { $0.id == task.id }))
        #expect(updated.name == "Book appointment")
        #expect(updated.basePrice == 300)
        #expect(updated.dueDate == dueDate)
    }

    // Behaviour: deleting a task should mark it deleted without removing the
    // record identity that sync still needs to reference.
    @Test func deleteTaskSetsDeletedAt() throws {
        let sut = makeSUT()
        let task = try #require(sut.addTask(name: "Inbox zero"))

        sut.deleteTask(id: task.id, deletedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let deleted = try #require(sut.tasks.first(where: { $0.id == task.id }))
        #expect(deleted.deletedAt != nil)
        #expect(sut.activeTasks.isEmpty)
    }

    // Behaviour: pinning a task should survive a store reload so its list
    // priority is not lost when the app restarts.
    @Test func pinTaskPersists() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("task-pin-persistence")
        let sut = TaskStore(storageURL: storageURL)
        let task = try #require(sut.addTask(name: "Important"))

        sut.setPinned(id: task.id, pinned: true)

        #expect(sut.tasks.first?.pinned == true)
        let reloaded = TaskStore(storageURL: storageURL)
        #expect(reloaded.tasks.first?.pinned == true)
    }

    // Behaviour: hiding a task should persist for sync without removing it
    // from the current list while the UI hiding rules are still pending.
    @Test func hideTaskPersistsWithoutFiltering() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("task-hidden-persistence")
        let sut = TaskStore(storageURL: storageURL)
        let task = try #require(sut.addTask(name: "Later"))

        sut.setHidden(id: task.id, hidden: true)

        #expect(sut.tasks.first?.hidden == true)
        #expect(sut.activeTasks.first?.hidden == true)
        let reloaded = TaskStore(storageURL: storageURL)
        #expect(reloaded.tasks.first?.hidden == true)
    }
}
