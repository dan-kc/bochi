import Foundation
import Testing
@testable import tofustash

@MainActor
struct ReminderStoreTests {
    private final class MockReminderNotificationScheduler: ReminderNotificationScheduling {
        private(set) var syncedDescriptors: [[ReminderNotificationDescriptor]] = []
        private(set) var canceledReminderIDs: [[RecordID]] = []

        func syncNotifications(for descriptors: [ReminderNotificationDescriptor]) {
            syncedDescriptors.append(descriptors)
        }

        func cancelNotifications(for reminderIDs: [RecordID]) {
            canceledReminderIDs.append(reminderIDs)
        }

        func reset() {
            syncedDescriptors.removeAll()
            canceledReminderIDs.removeAll()
        }
    }

    private struct TestContext {
        let taskStore: TaskStore
        let habitStore: HabitStore
        let scheduler: MockReminderNotificationScheduler
        let store: ReminderStore
    }

    private func makeContext() -> TestContext {
        let databaseURL = TestHelpers.makeTemporaryFileURL("reminders")
        let taskStore = TaskStore(storageURL: databaseURL)
        let habitStore = HabitStore(storageURL: databaseURL)
        let scheduler = MockReminderNotificationScheduler()
        let store = ReminderStore(
            storageURL: databaseURL,
            taskStore: taskStore,
            habitStore: habitStore,
            notificationScheduler: scheduler
        )
        return TestContext(
            taskStore: taskStore,
            habitStore: habitStore,
            scheduler: scheduler,
            store: store
        )
    }

    // Behaviour: A task can keep multiple reminders, and the persisted list
    // should come back sorted by scheduled time so the form always reads clearly.
    @Test func taskSupportsMultiplePersistedReminders() throws {
        let context = makeContext()
        let task = try #require(context.taskStore.addTask(name: "Submit report"))

        let later = Date(timeIntervalSince1970: 1_900_000_600)
        let sooner = Date(timeIntervalSince1970: 1_900_000_300)

        context.store.replaceReminders(
            for: .task(task.id),
            with: [
                ReminderDraft(id: "later-reminder", scheduledAt: later),
                ReminderDraft(id: "sooner-reminder", scheduledAt: sooner)
            ]
        )

        let reloaded = ReminderStore(
            storageURL: context.store.databaseURL,
            taskStore: context.taskStore,
            habitStore: context.habitStore,
            notificationScheduler: MockReminderNotificationScheduler()
        )

        #expect(reloaded.reminders(for: .task(task.id)).map(\.id) == ["sooner-reminder", "later-reminder"])
        #expect(reloaded.reminders(for: .task(task.id)).map(\.scheduledAt) == [sooner, later])
    }

    // Behaviour: launching the app should not touch the notification center
    // until the scene is active, because SpringBoard may still be finishing
    // the tapped-notification handoff during store initialization.
    @Test func initDoesNotEagerlySyncNotifications() {
        let context = makeContext()

        #expect(context.scheduler.syncedDescriptors.isEmpty)
        #expect(context.scheduler.canceledReminderIDs.isEmpty)
    }

    // Behaviour: expired reminders should stop appearing as active in the UI,
    // but the persisted record remains so the app can keep history locally.
    @Test func expiredRemindersAreExcludedFromActiveQueries() throws {
        let context = makeContext()
        let habit = try #require(context.habitStore.addHabit(name: "Read"))
        let past = Date().addingTimeInterval(-60)
        let future = Date().addingTimeInterval(300)

        context.store.replaceReminders(
            for: .habit(habit.id),
            with: [
                ReminderDraft(id: "past-reminder", scheduledAt: past),
                ReminderDraft(id: "future-reminder", scheduledAt: future)
            ]
        )

        #expect(context.store.reminders(for: .habit(habit.id)).count == 2)
        #expect(context.store.activeReminderDrafts(for: .habit(habit.id)).map(\.id) == ["future-reminder"])
    }

    // Behaviour: a habit can mix one-off and recurring reminders, and the
    // persisted list should reload with both reminder kinds intact.
    @Test func habitPersistsMixedOneOffAndRecurringReminders() throws {
        let context = makeContext()
        let habit = try #require(context.habitStore.addHabit(name: "Stretch"))
        let oneOffTime = Date(timeIntervalSince1970: 1_900_000_300)
        let recurringTime = Date(timeIntervalSince1970: 1_900_000_600)

        context.store.replaceReminders(
            for: .habit(habit.id),
            with: [
                ReminderDraft(id: "one-off-reminder", scheduledAt: oneOffTime),
                ReminderDraft(
                    id: "recurring-reminder",
                    scheduledAt: recurringTime,
                    recurrence: ReminderRecurrence(intervalValue: 3, unit: .hours)
                )
            ]
        )

        let reloaded = ReminderStore(
            storageURL: context.store.databaseURL,
            taskStore: context.taskStore,
            habitStore: context.habitStore,
            notificationScheduler: MockReminderNotificationScheduler()
        )

        let drafts = reloaded.reminderDrafts(for: .habit(habit.id))
        #expect(drafts.map(\.id) == ["one-off-reminder", "recurring-reminder"])
        #expect(drafts.first?.recurrence == nil)
        #expect(drafts.last?.recurrence == ReminderRecurrence(intervalValue: 3, unit: .hours))
    }

    // Behaviour: deleting one reminder should not disturb the other reminders
    // already scheduled for the same task.
    @Test func deletingOneReminderLeavesRemainingTaskReminders() throws {
        let context = makeContext()
        let task = try #require(context.taskStore.addTask(name: "Inbox zero"))
        let first = Date().addingTimeInterval(300)
        let second = Date().addingTimeInterval(600)

        context.store.replaceReminders(
            for: .task(task.id),
            with: [
                ReminderDraft(id: "first-reminder", scheduledAt: first),
                ReminderDraft(id: "second-reminder", scheduledAt: second)
            ]
        )

        context.store.replaceReminders(
            for: .task(task.id),
            with: [
                ReminderDraft(id: "second-reminder", scheduledAt: second)
            ]
        )

        #expect(context.store.reminders(for: .task(task.id)).map(\.id) == ["second-reminder"])
    }

    // Behaviour: completing a task should wipe only that task's future
    // reminders and report how many reminders were actually cleared.
    @Test func cancelFutureRemindersForTaskClearsOnlyFutureEntries() throws {
        let context = makeContext()
        let task = try #require(context.taskStore.addTask(name: "Pay rent"))
        let past = Date().addingTimeInterval(-120)
        let futureA = Date().addingTimeInterval(300)
        let futureB = Date().addingTimeInterval(900)

        context.store.replaceReminders(
            for: .task(task.id),
            with: [
                ReminderDraft(id: "past-reminder", scheduledAt: past),
                ReminderDraft(id: "future-reminder-a", scheduledAt: futureA),
                ReminderDraft(id: "future-reminder-b", scheduledAt: futureB)
            ]
        )

        let clearedCount = context.store.cancelFutureReminders(forTaskID: task.id)

        #expect(clearedCount == 2)
        #expect(context.store.reminders(for: .task(task.id)).map(\.id) == ["past-reminder"])
        #expect(context.scheduler.canceledReminderIDs.flatMap { $0 }.contains("future-reminder-a"))
        #expect(context.scheduler.canceledReminderIDs.flatMap { $0 }.contains("future-reminder-b"))
    }

    // Behaviour: the notification scheduler should only receive future reminders
    // for live entities, never expired ones.
    @Test func schedulerReceivesOnlyFutureReminders() throws {
        let context = makeContext()
        let task = try #require(context.taskStore.addTask(name: "Call bank"))
        let past = Date().addingTimeInterval(-30)
        let future = Date().addingTimeInterval(300)

        context.store.replaceReminders(
            for: .task(task.id),
            with: [
                ReminderDraft(id: "past-reminder", scheduledAt: past),
                ReminderDraft(id: "future-reminder", scheduledAt: future)
            ]
        )

        let latestSync = try #require(context.scheduler.syncedDescriptors.last)
        #expect(latestSync.map(\.reminderID) == ["future-reminder"])
        #expect(latestSync.first?.title == "Task Reminder")
        #expect(latestSync.first?.taskID == task.id)
    }

    // Behaviour: recurring reminders should schedule their next future
    // occurrence instead of being treated like a one-shot at the original time.
    @Test func schedulerUsesNextOccurrenceForRecurringHabitReminder() throws {
        let context = makeContext()
        let habit = try #require(context.habitStore.addHabit(name: "Meditate"))
        let startAt = Date().addingTimeInterval(-90 * 60)

        context.store.replaceReminders(
            for: .habit(habit.id),
            with: [
                ReminderDraft(
                    id: "recurring-habit-reminder",
                    scheduledAt: startAt,
                    recurrence: ReminderRecurrence(intervalValue: 1, unit: .hours)
                )
            ]
        )

        let latestSync = try #require(context.scheduler.syncedDescriptors.last)
        let scheduledReminder = try #require(latestSync.first)

        #expect(scheduledReminder.reminderID == "recurring-habit-reminder")
        #expect(scheduledReminder.title == "Habit Reminder")
        #expect(scheduledReminder.scheduledAt > context.store.referenceDate)
    }

    // Behaviour: completing a task should clear recurring reminders whose next
    // occurrence is still in the future, even if the original start time passed.
    @Test func cancelFutureRemindersForTaskClearsRecurringReminderAfterStartTime() throws {
        let context = makeContext()
        let task = try #require(context.taskStore.addTask(name: "Stretch"))
        let startAt = Date().addingTimeInterval(-90 * 60)

        context.store.replaceReminders(
            for: .task(task.id),
            with: [
                ReminderDraft(
                    id: "recurring-task-reminder",
                    scheduledAt: startAt,
                    recurrence: ReminderRecurrence(intervalValue: 1, unit: .hours)
                )
            ]
        )

        let clearedCount = context.store.cancelFutureReminders(forTaskID: task.id)

        #expect(clearedCount == 1)
        #expect(context.store.reminders(for: .task(task.id)).isEmpty)
        #expect(context.scheduler.canceledReminderIDs.flatMap { $0 }.contains("recurring-task-reminder"))
    }

    // Behaviour: switching signed-in owners should only swap the reminder data
    // in memory; actual notification reconciliation waits until the app is active.
    @Test func switchingOwnerDoesNotEagerlySyncNotifications() throws {
        let context = makeContext()
        let task = try #require(context.taskStore.addTask(name: "Plan trip"))
        let reminderTime = Date().addingTimeInterval(600)

        context.store.replaceReminders(
            for: .task(task.id),
            with: [ReminderDraft(id: "trip-reminder", scheduledAt: reminderTime)]
        )

        #expect(context.scheduler.syncedDescriptors.count == 1)

        context.scheduler.reset()
        context.store.setCurrentOwner("user-123")

        #expect(context.scheduler.syncedDescriptors.isEmpty)
        #expect(context.scheduler.canceledReminderIDs.isEmpty)
    }
}
