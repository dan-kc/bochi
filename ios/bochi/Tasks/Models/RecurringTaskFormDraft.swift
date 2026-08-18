import Foundation

struct RecurringTaskFormDraft: Equatable {
    var recurringTaskID = RecordID()
    var name = ""
    var description = ""
    var frequency: Double? = nil
    var lockoutDurationSeconds: Int? = nil
    var basePrice = 100
    var timerSelection: EntityTimerSelection = .none
    var reminderDrafts: [ReminderDraft] = []

    var trimmedName: String {
        EntityFormSupport.trimmedName(name)
    }

    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init() {}

    init(prefill: RecurringTaskFormSnapshot) {
        recurringTaskID = prefill.recurringTaskId
        name = prefill.name
        description = prefill.description
        frequency = prefill.frequency
        lockoutDurationSeconds = prefill.lockoutDurationSeconds
        basePrice = prefill.basePrice
        timerSelection = prefill.timerSelection
        reminderDrafts = prefill.reminderDrafts
    }

    init(recurringTask: RecurringTask, reminderDrafts: [ReminderDraft]) {
        recurringTaskID = recurringTask.id
        name = recurringTask.name
        description = recurringTask.description
        frequency = recurringTask.frequency
        lockoutDurationSeconds = recurringTask.lockoutDurationSeconds
        basePrice = recurringTask.basePrice
        timerSelection = recurringTask.timerSelection
        self.reminderDrafts = reminderDrafts
    }

    func activeReminderDrafts(now: Date) -> [ReminderDraft] {
        ReminderDraftSupport.active(reminderDrafts, now: now)
    }

    func recurringTask(existingRecurringTask: RecurringTask?, now: Date = Date()) -> RecurringTask {
        let autoSavedName = EntityFormSupport.trimmedName(name)
        let persistedName = autoSavedName.isEmpty ? (existingRecurringTask?.name ?? "") : autoSavedName

        return RecurringTask(
            id: existingRecurringTask?.id ?? recurringTaskID,
            name: persistedName,
            description: description,
            createdAt: existingRecurringTask?.createdAt ?? now,
            updatedAt: now,
            deletedAt: existingRecurringTask?.deletedAt,
            frequency: frequency,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: basePrice,
            pinned: existingRecurringTask?.pinned ?? false,
            hidden: existingRecurringTask?.hidden ?? false,
            timerSelection: timerSelection,
            serverRevision: existingRecurringTask?.serverRevision
        )
    }

    func snapshot(tagIDs: [RecordID]) -> RecurringTaskFormSnapshot {
        RecurringTaskFormSnapshot(
            name: name,
            description: description,
            frequency: frequency,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: basePrice,
            timerSelection: timerSelection,
            reminderDrafts: reminderDrafts,
            recurringTaskId: recurringTaskID,
            tagIDs: tagIDs
        )
    }
}
