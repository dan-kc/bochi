import Foundation

@MainActor
final class ReminderNotificationReconciler {
    private let reminderStore: ReminderStore
    private let taskStore: TaskStore
    private let recurringTaskStore: RecurringTaskStore
    private let tradeStore: TradeStore
    private let notificationScheduler: ReminderNotificationScheduling

    private var nextExpiryRefreshTask: Task<Void, Never>?

    init(
        reminderStore: ReminderStore,
        taskStore: TaskStore,
        recurringTaskStore: RecurringTaskStore,
        tradeStore: TradeStore,
        notificationScheduler: ReminderNotificationScheduling
    ) {
        self.reminderStore = reminderStore
        self.taskStore = taskStore
        self.recurringTaskStore = recurringTaskStore
        self.tradeStore = tradeStore
        self.notificationScheduler = notificationScheduler
    }

    func reconcileNotifications(hasPremiumAccess: Bool) {
        let referenceDate = Date()
        reminderStore.updateNotificationReferenceDate(referenceDate)

        guard hasPremiumAccess else {
            let activeIDs = reminderStore.allReminderIDs()
            if !activeIDs.isEmpty {
                notificationScheduler.cancelNotifications(for: activeIDs)
            }
            cancelNextExpiryRefresh()
            return
        }

        let descriptors = schedulableReminders(at: referenceDate)
            .compactMap { notificationDescriptor(for: $0, now: referenceDate) }
            .sorted(by: sortNotificationDescriptors)
        let activeIDs = Set(descriptors.map(\.reminderID))
        let removedIDs = Set(reminderStore.allReminderIDs()).subtracting(activeIDs)

        if !removedIDs.isEmpty {
            notificationScheduler.cancelNotifications(for: Array(removedIDs))
        }
        if !descriptors.isEmpty {
            notificationScheduler.syncNotifications(for: descriptors)
        }

        scheduleNextExpiryRefresh(from: descriptors)
    }

    func cancelNotifications(for reminderIDs: [RecordID]) {
        notificationScheduler.cancelNotifications(for: reminderIDs)
    }

    private func notificationDescriptor(
        for reminder: EntityReminder,
        now: Date
    ) -> ReminderNotificationDescriptor? {
        guard let nextOccurrence = ReminderDraftSupport.nextOccurrence(for: reminderStore.draft(for: reminder), now: now) else {
            return nil
        }

        if let taskID = reminder.taskId,
           let task = taskStore.tasks.first(where: { $0.id == taskID && $0.deletedAt == nil }),
           tradeStore.latestTaskTrade(taskId: taskID, includeRefunded: false) == nil {
            return ReminderNotificationDescriptor(
                reminderID: reminder.id,
                scheduledAt: nextOccurrence,
                title: "Task Reminder",
                body: task.name,
                taskID: task.id,
                recurringTaskID: nil
            )
        }

        if let recurringTaskID = reminder.recurringTaskId,
           let recurringTask = recurringTaskStore.recurringTasks.first(where: { $0.id == recurringTaskID && $0.deletedAt == nil }) {
            return ReminderNotificationDescriptor(
                reminderID: reminder.id,
                scheduledAt: nextOccurrence,
                title: "Recurring Task Reminder",
                body: recurringTask.name,
                taskID: nil,
                recurringTaskID: recurringTask.id
            )
        }

        return nil
    }

    private func schedulableReminders(at now: Date) -> [EntityReminder] {
        reminderStore.reminders
            .filter { $0.deletedAt == nil }
            .filter { reminder in
                guard ReminderDraftSupport.nextOccurrence(for: reminderStore.draft(for: reminder), now: now) != nil else {
                    return false
                }

                if let taskID = reminder.taskId {
                    return taskStore.tasks.contains {
                        $0.id == taskID && $0.deletedAt == nil
                    } && tradeStore.latestTaskTrade(taskId: taskID, includeRefunded: false) == nil
                }

                if let recurringTaskID = reminder.recurringTaskId {
                    return recurringTaskStore.recurringTasks.contains {
                        $0.id == recurringTaskID && $0.deletedAt == nil
                    }
                }

                return false
            }
            .sorted(by: sortReminders)
    }

    private func scheduleNextExpiryRefresh(from activeDescriptors: [ReminderNotificationDescriptor]) {
        cancelNextExpiryRefresh()

        guard let nextReminder = activeDescriptors.first else { return }

        nextExpiryRefreshTask = Task { [weak self] in
            let secondsUntilRefresh = max(nextReminder.scheduledAt.timeIntervalSinceNow + 1, 1)
            try? await Task.sleep(nanoseconds: UInt64(secondsUntilRefresh * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.reminderStore.markNotificationScheduleChanged()
            }
        }
    }

    private func cancelNextExpiryRefresh() {
        nextExpiryRefreshTask?.cancel()
        nextExpiryRefreshTask = nil
    }

    private func sortReminders(_ lhs: EntityReminder, _ rhs: EntityReminder) -> Bool {
        if lhs.scheduledAt == rhs.scheduledAt {
            return lhs.id.rawValue < rhs.id.rawValue
        }

        return lhs.scheduledAt < rhs.scheduledAt
    }

    private func sortNotificationDescriptors(
        _ lhs: ReminderNotificationDescriptor,
        _ rhs: ReminderNotificationDescriptor
    ) -> Bool {
        if lhs.scheduledAt == rhs.scheduledAt {
            return lhs.reminderID.rawValue < rhs.reminderID.rawValue
        }

        return lhs.scheduledAt < rhs.scheduledAt
    }
}
