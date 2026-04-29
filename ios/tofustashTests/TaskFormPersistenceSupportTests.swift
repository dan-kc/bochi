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
}
