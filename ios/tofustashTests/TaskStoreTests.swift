import Foundation
import Testing
@testable import tofustash

@MainActor
struct TaskStoreTests {
    private func makeSUT() -> TaskStore {
        TaskStore(storageURL: TestHelpers.makeTemporaryFileURL("tasks"))
    }

    // Behaviour: When the app first loads with no task data, the task list is empty.
    @Test func initialStoreHasNoTasks() {
        let sut = makeSUT()
        #expect(sut.tasks.isEmpty)
        #expect(sut.activeTasks.isEmpty)
        #expect(sut.completedTasks.isEmpty)
    }

    // Behaviour: Saving a task should persist its user-facing fields, including due date.
    @Test func addTaskAppendsToTasks() {
        let sut = makeSUT()
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)

        let task = sut.addTask(
            name: "Submit report",
            description: "Finish the draft",
            difficultyTier: .medium,
            durationSeconds: 900,
            commitment: 3,
            dueDate: dueDate
        )

        #expect(sut.tasks.count == 1)
        #expect(task?.name == "Submit report")
        #expect(task?.dueDate == dueDate)
    }

    // Behaviour: Completing a one-shot task should mark it completed and remove
    // it from the active list without deleting the record.
    @Test func completeTaskSetsCompletedAtAndRemovesItFromActiveTasks() throws {
        let sut = makeSUT()
        let task = try #require(sut.addTask(name: "File taxes"))

        sut.completeTask(id: task.id, completedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let completed = try #require(sut.tasks.first(where: { $0.id == task.id }))
        #expect(completed.completedAt != nil)
        #expect(sut.activeTasks.isEmpty)
        #expect(sut.completedTasks.map(\.id) == [task.id])
    }

    // Behaviour: Editing a task should not clear the completion flag unless the
    // app explicitly reopens it.
    @Test func updateTaskPreservesCompletedAtByDefault() throws {
        let sut = makeSUT()
        let task = try #require(sut.addTask(name: "Book appointment"))
        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)

        sut.completeTask(id: task.id, completedAt: completedAt)
        sut.updateTask(id: task.id, name: "Book dentist appointment")

        #expect(sut.tasks.first?.completedAt == completedAt)
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
            difficultyTier: .some(.hard),
            dueDate: .some(dueDate)
        )

        let updated = try #require(sut.tasks.first(where: { $0.id == task.id }))
        #expect(updated.name == "Book appointment")
        #expect(updated.difficultyTier == .hard)
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
    }

    // Behaviour: once a task is deleted from the list, it should immediately
    // disappear from the active collection that powers the visible task screen.
    @Test func deletedTaskIsExcludedFromActiveTasks() throws {
        let sut = makeSUT()
        let task = try #require(sut.addTask(name: "Clean inbox"))

        sut.deleteTask(id: task.id)

        #expect(sut.activeTasks.isEmpty)
        #expect(sut.tasks.count == 1)
    }
}
