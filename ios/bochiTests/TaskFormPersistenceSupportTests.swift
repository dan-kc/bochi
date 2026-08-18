import Foundation
import Testing
@testable import bochi

@MainActor
struct TaskFormPersistenceSupportTests {
    // Behaviour: if a new task fails validation, task reminders should stay
    // local to the sheet instead of persisting orphan reminder rows.
    @Test func invalidNewTaskDoesNotPersistReminders() {
        let storageURL = TestHelpers.makeTemporaryFileURL("task-form-persistence")
        let taskStore = TaskStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)
        let reminderStore = ReminderStore(storageURL: storageURL)
        let taskID = RecordID()

        let persistedTask = TaskFormPersistenceSupport.persistTask(
            task: nil,
            taskID: taskID,
            name: String(repeating: "x", count: 101),
            description: "",
            basePrice: 200,
            dueDate: nil,
            reminderDrafts: [ReminderDraft(scheduledAt: Date().addingTimeInterval(300))],
            taskDependencies: [],
            recurringTaskDependencies: [],
            taskStore: taskStore,
            taskDependencyStore: dependencyStore,
            reminderStore: reminderStore
        )

        #expect(persistedTask == nil)
        #expect(taskStore.tasks.isEmpty)
        #expect(reminderStore.reminders(for: .task(taskID)).isEmpty)
    }

    // Behaviour: editing an existing task should replace the saved reminders so
    // recurringTask-style auto-save keeps the reminder list in sync with the last edit.
    @Test func existingTaskEditReplacesReminders() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("task-form-persistence")
        let taskStore = TaskStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)
        let reminderStore = ReminderStore(storageURL: storageURL)
        let existingTask = try #require(taskStore.addTask(name: "Plan trip"))

        reminderStore.replaceReminders(
            for: .task(existingTask.id),
            with: [ReminderDraft(scheduledAt: Date().addingTimeInterval(300))]
        )

        let replacementReminder = ReminderDraft(scheduledAt: Date().addingTimeInterval(1_200))
        let persistedTask = TaskFormPersistenceSupport.persistTask(
            task: existingTask,
            taskID: existingTask.id,
            name: existingTask.name,
            description: existingTask.description,
            basePrice: existingTask.basePrice,
            dueDate: existingTask.dueDate,
            reminderDrafts: [replacementReminder],
            taskDependencies: [],
            recurringTaskDependencies: [],
            taskStore: taskStore,
            taskDependencyStore: dependencyStore,
            reminderStore: reminderStore
        )

        let savedTask = try #require(persistedTask)
        #expect(savedTask.id == existingTask.id)
        let persistedReminders = reminderStore.reminderDrafts(for: .task(existingTask.id))
        #expect(persistedReminders.count == 1)
        let persistedScheduledAt = try #require(persistedReminders.first?.scheduledAt)
        #expect(abs(persistedScheduledAt.timeIntervalSince(replacementReminder.scheduledAt)) < 1)
    }

    // Behaviour: saving a task should not delete its reminders, so task history
    // changes do not discard any future recurring schedule.
    @Test func completedTaskKeepsPersistedReminders() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("task-form-persistence")
        let taskStore = TaskStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)
        let reminderStore = ReminderStore(storageURL: storageURL)
        let existingTask = try #require(taskStore.addTask(name: "Submit report"))
        let reminder = ReminderDraft(scheduledAt: Date().addingTimeInterval(1_200))

        reminderStore.replaceReminders(for: .task(existingTask.id), with: [reminder])

        let persistedTask = TaskFormPersistenceSupport.persistTask(
            task: existingTask,
            taskID: existingTask.id,
            name: existingTask.name,
            description: existingTask.description,
            basePrice: existingTask.basePrice,
            dueDate: existingTask.dueDate,
            reminderDrafts: [reminder],
            taskDependencies: [],
            recurringTaskDependencies: [],
            taskStore: taskStore,
            taskDependencyStore: dependencyStore,
            reminderStore: reminderStore
        )

        let savedTask = try #require(persistedTask)
        #expect(savedTask.id == existingTask.id)
        let persistedReminders = reminderStore.reminderDrafts(for: .task(existingTask.id))
        #expect(persistedReminders.count == 1)
    }

    // Behaviour: editing an existing task should replace the saved dependency
    // list so auto-save keeps the latest prerequisite choices.
    @Test func existingTaskEditReplacesDependencies() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("task-form-dependencies")
        let taskStore = TaskStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)
        let reminderStore = ReminderStore(storageURL: storageURL)
        let prerequisiteTask = try #require(taskStore.addTask(name: "Draft report"))
        let existingTask = try #require(taskStore.addTask(name: "Send report"))

        dependencyStore.replaceDependencies(
            for: existingTask.id,
            taskDependencies: [
                TaskTaskDependency(
                    taskId: existingTask.id,
                    dependsOnTaskId: prerequisiteTask.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil
                )
            ],
            recurringTaskDependencies: [],
            shouldNotifySync: false
        )

        let replacementTask = try #require(taskStore.addTask(name: "Proofread report"))
        let persistedTask = TaskFormPersistenceSupport.persistTask(
            task: existingTask,
            taskID: existingTask.id,
            name: existingTask.name,
            description: existingTask.description,
            basePrice: existingTask.basePrice,
            dueDate: existingTask.dueDate,
            reminderDrafts: [],
            taskDependencies: [
                TaskTaskDependency(
                    taskId: existingTask.id,
                    dependsOnTaskId: replacementTask.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_100),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
                    deletedAt: nil
                )
            ],
            recurringTaskDependencies: [],
            taskStore: taskStore,
            taskDependencyStore: dependencyStore,
            reminderStore: reminderStore
        )

        let savedTask = try #require(persistedTask)
        #expect(savedTask.id == existingTask.id)
        let persistedDependencies = dependencyStore.activeTaskDependencies(for: existingTask.id)
        #expect(persistedDependencies.map(\.dependsOnTaskId) == [replacementTask.id])
    }

    // Behaviour: removing a blocking dependency in the task form should take
    // effect immediately, so the user can complete the task without reopening it.
    @Test func removingDependencyThenCompletingTaskSucceeds() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("task-form-remove-dependency")
        let taskStore = TaskStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        let reminderStore = ReminderStore(storageURL: storageURL)

        let prerequisiteTask = try #require(taskStore.addTask(name: "Draft report"))
        let blockedTask = try #require(taskStore.addTask(name: "Send report"))

        dependencyStore.replaceDependencies(
            for: blockedTask.id,
            taskDependencies: [
                TaskTaskDependency(
                    taskId: blockedTask.id,
                    dependsOnTaskId: prerequisiteTask.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil
                )
            ],
            recurringTaskDependencies: [],
            shouldNotifySync: false
        )

        let persistedTask = try #require(
            TaskFormPersistenceSupport.persistTask(
                task: blockedTask,
                taskID: blockedTask.id,
                name: blockedTask.name,
                description: blockedTask.description,
                basePrice: blockedTask.basePrice,
                dueDate: blockedTask.dueDate,
                reminderDrafts: [],
                taskDependencies: [],
                recurringTaskDependencies: [],
                taskStore: taskStore,
                taskDependencyStore: dependencyStore,
                reminderStore: reminderStore
            )
        )

        #expect(
            !dependencyStore.isTaskBlocked(
                persistedTask,
                taskStore: taskStore,
                tradeStore: tradeStore
            )
        )

        let completedAt = try #require(
            TaskCompletionService.completeTask(
                taskID: blockedTask.id,
                sourceName: blockedTask.name,
                price: 120,
                tradeStore: tradeStore,
                taskStore: taskStore,
                balanceStore: balanceStore,
                claimDate: Date(timeIntervalSince1970: 1_800_000_100)
            )
        )

        #expect(completedAt == Date(timeIntervalSince1970: 1_800_000_100))
    }
}
