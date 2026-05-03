import Foundation
import Testing
@testable import tofustash

@MainActor
struct TaskFormPersistenceSupportTests {
    private final class MockReminderNotificationScheduler: ReminderNotificationScheduling {
        private(set) var syncedDescriptors: [[ReminderNotificationDescriptor]] = []
        private(set) var canceledReminderIDs: [[RecordID]] = []

        func syncNotifications(for descriptors: [ReminderNotificationDescriptor]) {
            syncedDescriptors.append(descriptors)
        }

        func cancelNotifications(for reminderIDs: [RecordID]) {
            canceledReminderIDs.append(reminderIDs)
        }
    }

    // Behaviour: if a new task fails validation, task reminders should stay
    // local to the sheet instead of persisting orphan reminder rows.
    @Test func invalidNewTaskDoesNotPersistReminders() {
        let storageURL = TestHelpers.makeTemporaryFileURL("task-form-persistence")
        let taskStore = TaskStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)
        let reminderStore = ReminderStore(
            storageURL: storageURL,
            taskStore: taskStore,
            habitStore: HabitStore(storageURL: storageURL),
            notificationScheduler: MockReminderNotificationScheduler()
        )
        let taskID = RecordID()

        let persistedTask = TaskFormPersistenceSupport.persistTask(
            task: nil,
            taskID: taskID,
            name: String(repeating: "x", count: 101),
            description: "",
            difficultyTier: nil,
            durationSeconds: nil,
            commitment: nil,
            dueDate: nil,
            completedAt: nil,
            reminderDrafts: [ReminderDraft(scheduledAt: Date().addingTimeInterval(300))],
            taskDependencies: [],
            habitDependencies: [],
            taskStore: taskStore,
            taskDependencyStore: dependencyStore,
            reminderStore: reminderStore
        )

        #expect(persistedTask == nil)
        #expect(taskStore.tasks.isEmpty)
        #expect(reminderStore.reminders(for: .task(taskID)).isEmpty)
    }

    // Behaviour: editing an existing task should replace the saved reminders so
    // habit-style auto-save keeps the reminder list in sync with the last edit.
    @Test func existingTaskEditReplacesReminders() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("task-form-persistence")
        let taskStore = TaskStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)
        let reminderStore = ReminderStore(
            storageURL: storageURL,
            taskStore: taskStore,
            habitStore: HabitStore(storageURL: storageURL),
            notificationScheduler: MockReminderNotificationScheduler()
        )
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
            difficultyTier: existingTask.difficultyTier,
            durationSeconds: existingTask.durationSeconds,
            commitment: existingTask.commitment,
            dueDate: existingTask.dueDate,
            completedAt: existingTask.completedAt,
            reminderDrafts: [replacementReminder],
            taskDependencies: [],
            habitDependencies: [],
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

    // Behaviour: marking a task complete should not delete its reminders, so
    // completed tasks can still show and edit any future recurring schedule.
    @Test func completedTaskKeepsPersistedReminders() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("task-form-persistence")
        let taskStore = TaskStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)
        let reminderStore = ReminderStore(
            storageURL: storageURL,
            taskStore: taskStore,
            habitStore: HabitStore(storageURL: storageURL),
            notificationScheduler: MockReminderNotificationScheduler()
        )
        let existingTask = try #require(taskStore.addTask(name: "Submit report"))
        let reminder = ReminderDraft(scheduledAt: Date().addingTimeInterval(1_200))

        reminderStore.replaceReminders(for: .task(existingTask.id), with: [reminder])

        let persistedTask = TaskFormPersistenceSupport.persistTask(
            task: existingTask,
            taskID: existingTask.id,
            name: existingTask.name,
            description: existingTask.description,
            difficultyTier: existingTask.difficultyTier,
            durationSeconds: existingTask.durationSeconds,
            commitment: existingTask.commitment,
            dueDate: existingTask.dueDate,
            completedAt: Date(),
            reminderDrafts: [reminder],
            taskDependencies: [],
            habitDependencies: [],
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
        let reminderStore = ReminderStore(
            storageURL: storageURL,
            taskStore: taskStore,
            habitStore: HabitStore(storageURL: storageURL),
            notificationScheduler: MockReminderNotificationScheduler()
        )
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
            habitDependencies: [],
            shouldNotifySync: false
        )

        let replacementTask = try #require(taskStore.addTask(name: "Proofread report"))
        let persistedTask = TaskFormPersistenceSupport.persistTask(
            task: existingTask,
            taskID: existingTask.id,
            name: existingTask.name,
            description: existingTask.description,
            difficultyTier: existingTask.difficultyTier,
            durationSeconds: existingTask.durationSeconds,
            commitment: existingTask.commitment,
            dueDate: existingTask.dueDate,
            completedAt: existingTask.completedAt,
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
            habitDependencies: [],
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
        let reminderStore = ReminderStore(
            storageURL: storageURL,
            taskStore: taskStore,
            habitStore: HabitStore(storageURL: storageURL),
            notificationScheduler: MockReminderNotificationScheduler()
        )

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
            habitDependencies: [],
            shouldNotifySync: false
        )

        let persistedTask = try #require(
            TaskFormPersistenceSupport.persistTask(
                task: blockedTask,
                taskID: blockedTask.id,
                name: blockedTask.name,
                description: blockedTask.description,
                difficultyTier: blockedTask.difficultyTier,
                durationSeconds: blockedTask.durationSeconds,
                commitment: blockedTask.commitment,
                dueDate: blockedTask.dueDate,
                completedAt: blockedTask.completedAt,
                reminderDrafts: [],
                taskDependencies: [],
                habitDependencies: [],
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
            TaskCompletionSupport.completeTask(
                taskID: blockedTask.id,
                sourceName: blockedTask.name,
                reward: 120,
                tradeStore: tradeStore,
                taskStore: taskStore,
                balanceStore: balanceStore,
                claimDate: Date(timeIntervalSince1970: 1_800_000_100)
            )
        )

        #expect(completedAt == Date(timeIntervalSince1970: 1_800_000_100))
    }
}
