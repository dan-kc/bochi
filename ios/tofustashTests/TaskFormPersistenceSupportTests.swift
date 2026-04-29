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
        let reminderStore = ReminderStore(
            storageURL: storageURL,
            taskStore: taskStore,
            habitStore: HabitStore(storageURL: storageURL),
            notificationScheduler: MockReminderNotificationScheduler()
        )
        let taskID = RecordID()

        let didPersist = TaskFormPersistenceSupport.persistTask(
            task: nil,
            taskID: taskID,
            name: String(repeating: "x", count: 101),
            description: "",
            difficultyTier: nil,
            durationSeconds: nil,
            skipConsequence: nil,
            dueDate: nil,
            completedAt: nil,
            reminderDrafts: [ReminderDraft(scheduledAt: Date().addingTimeInterval(300))],
            taskStore: taskStore,
            reminderStore: reminderStore
        )

        #expect(didPersist == false)
        #expect(taskStore.tasks.isEmpty)
        #expect(reminderStore.reminders(for: .task(taskID)).isEmpty)
    }

    // Behaviour: editing an existing task should replace the saved reminders so
    // habit-style auto-save keeps the reminder list in sync with the last edit.
    @Test func existingTaskEditReplacesReminders() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("task-form-persistence")
        let taskStore = TaskStore(storageURL: storageURL)
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
        let didPersist = TaskFormPersistenceSupport.persistTask(
            task: existingTask,
            taskID: existingTask.id,
            name: existingTask.name,
            description: existingTask.description,
            difficultyTier: existingTask.difficultyTier,
            durationSeconds: existingTask.durationSeconds,
            skipConsequence: existingTask.skipConsequence,
            dueDate: existingTask.dueDate,
            completedAt: existingTask.completedAt,
            reminderDrafts: [replacementReminder],
            taskStore: taskStore,
            reminderStore: reminderStore
        )

        #expect(didPersist == true)
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
        let reminderStore = ReminderStore(
            storageURL: storageURL,
            taskStore: taskStore,
            habitStore: HabitStore(storageURL: storageURL),
            notificationScheduler: MockReminderNotificationScheduler()
        )
        let existingTask = try #require(taskStore.addTask(name: "Submit report"))
        let reminder = ReminderDraft(scheduledAt: Date().addingTimeInterval(1_200))

        reminderStore.replaceReminders(for: .task(existingTask.id), with: [reminder])

        let didPersist = TaskFormPersistenceSupport.persistTask(
            task: existingTask,
            taskID: existingTask.id,
            name: existingTask.name,
            description: existingTask.description,
            difficultyTier: existingTask.difficultyTier,
            durationSeconds: existingTask.durationSeconds,
            skipConsequence: existingTask.skipConsequence,
            dueDate: existingTask.dueDate,
            completedAt: Date(),
            reminderDrafts: [reminder],
            taskStore: taskStore,
            reminderStore: reminderStore
        )

        #expect(didPersist == true)
        let persistedReminders = reminderStore.reminderDrafts(for: .task(existingTask.id))
        #expect(persistedReminders.count == 1)
    }
}
