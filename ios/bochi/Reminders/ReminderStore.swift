import Foundation

struct EntityReminder: Identifiable, Equatable, Sendable, OwnerScopedRecord {
    let id: RecordID
    let taskId: RecordID?
    let recurringTaskId: RecordID?
    let scheduledAt: Date
    let recurrence: ReminderRecurrence?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

@Observable
@MainActor
final class ReminderStore {
    let databaseURL: URL

    private let database = AppDatabase.shared

    private(set) var currentOwnerID: String
    private(set) var reminders: [EntityReminder] = []
    private(set) var referenceDate = Date()
    private(set) var notificationScheduleRevision = 0

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = StorageOwner.local
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        reminders = loadReminders(ownerID: initialOwnerID)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        reminders = loadReminders(ownerID: ownerID)
        markNotificationScheduleChanged()
    }

    func migrateReminders(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        guard sourceOwnerID != destinationOwnerID else { return }
        let source = loadReminders(ownerID: sourceOwnerID)
        let destination = loadReminders(ownerID: destinationOwnerID)
        let merged = OwnerScopedRecordSupport.mergeRecords(local: destination, remote: source)

        try replaceRows(ownerID: sourceOwnerID, reminders: [], on: databaseHandle)
        try replaceRows(ownerID: destinationOwnerID, reminders: merged, on: databaseHandle)
    }

    func reminders(for target: ReminderOwnerTarget) -> [EntityReminder] {
        reminders
            .filter { reminder in
                reminder.deletedAt == nil
                    && reminder.taskId == target.taskID
                    && reminder.recurringTaskId == target.recurringTaskID
            }
            .sorted(by: sortReminders)
    }

    func reminderDrafts(for target: ReminderOwnerTarget) -> [ReminderDraft] {
        reminders(for: target).map(draft(for:))
    }

    func activeReminderDrafts(for target: ReminderOwnerTarget) -> [ReminderDraft] {
        ReminderDraftSupport.active(reminderDrafts(for: target), now: referenceDate)
    }

    func replaceReminders(for target: ReminderOwnerTarget, with drafts: [ReminderDraft]) {
        let canonicalDrafts = drafts.sorted(by: ReminderDraftSupport.sortDrafts)
        let existing = reminders(for: target)
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let retainedIDs = Set(canonicalDrafts.map(\.id))
        let now = Date()

        do {
            try database.transaction(at: databaseURL) { db in
                for draft in canonicalDrafts {
                    let existingReminder = existingByID[draft.id]
                    let row = EntityReminder(
                        id: draft.id,
                        taskId: target.taskID,
                        recurringTaskId: target.recurringTaskID,
                        scheduledAt: draft.scheduledAt,
                        recurrence: draft.recurrence,
                        createdAt: existingReminder?.createdAt ?? now,
                        updatedAt: now,
                        deletedAt: nil
                    )
                    try self.upsert(row, ownerID: self.currentOwnerID, on: db)
                }

                for existingReminder in existing where !retainedIDs.contains(existingReminder.id) {
                    let deletedReminder = EntityReminder(
                        id: existingReminder.id,
                        taskId: existingReminder.taskId,
                        recurringTaskId: existingReminder.recurringTaskId,
                        scheduledAt: existingReminder.scheduledAt,
                        recurrence: existingReminder.recurrence,
                        createdAt: existingReminder.createdAt,
                        updatedAt: now,
                        deletedAt: now
                    )
                    try self.upsert(deletedReminder, ownerID: self.currentOwnerID, on: db)
                }
            }
        } catch {
            assertionFailure("Failed to replace reminders: \(error)")
            return
        }

        refreshCurrentReminders()
    }

    func cancelFutureReminders(forTaskID taskID: RecordID) -> Int {
        let now = Date()
        referenceDate = now
        let visibleFutureReminders = reminders(for: .task(taskID))
            .filter { reminder in
                ReminderDraftSupport.nextOccurrence(for: draft(for: reminder), now: now) != nil
            }

        guard !visibleFutureReminders.isEmpty else { return 0 }

        do {
            try database.transaction(at: databaseURL) { db in
                for reminder in visibleFutureReminders {
                    let deletedReminder = EntityReminder(
                        id: reminder.id,
                        taskId: reminder.taskId,
                        recurringTaskId: reminder.recurringTaskId,
                        scheduledAt: reminder.scheduledAt,
                        recurrence: reminder.recurrence,
                        createdAt: reminder.createdAt,
                        updatedAt: now,
                        deletedAt: now
                    )
                    try self.upsert(deletedReminder, ownerID: self.currentOwnerID, on: db)
                }
            }
        } catch {
            assertionFailure("Failed to cancel task reminders: \(error)")
            return 0
        }

        refreshCurrentReminders()
        return visibleFutureReminders.count
    }

    func deleteAllReminders(for target: ReminderOwnerTarget) {
        let existing = reminders(for: target)
        guard !existing.isEmpty else { return }
        let now = Date()

        do {
            try database.transaction(at: databaseURL) { db in
                for reminder in existing {
                    let deletedReminder = EntityReminder(
                        id: reminder.id,
                        taskId: reminder.taskId,
                        recurringTaskId: reminder.recurringTaskId,
                        scheduledAt: reminder.scheduledAt,
                        recurrence: reminder.recurrence,
                        createdAt: reminder.createdAt,
                        updatedAt: now,
                        deletedAt: now
                    )
                    try self.upsert(deletedReminder, ownerID: self.currentOwnerID, on: db)
                }
            }
        } catch {
            assertionFailure("Failed to delete reminders: \(error)")
            return
        }

        refreshCurrentReminders()
    }

    private func refreshCurrentReminders() {
        reminders = loadReminders(ownerID: currentOwnerID)
        markNotificationScheduleChanged()
    }

    func updateNotificationReferenceDate(_ date: Date) {
        referenceDate = date
    }

    func markNotificationScheduleChanged() {
        notificationScheduleRevision += 1
    }

    func draft(for reminder: EntityReminder) -> ReminderDraft {
        ReminderDraft(
            id: reminder.id,
            scheduledAt: reminder.scheduledAt,
            recurrence: reminder.recurrence
        )
    }

    private func upsert(
        _ reminder: EntityReminder,
        ownerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try database.execute(
            """
            INSERT INTO reminders (
                id, owner_id, task_id, recurring_task_id, scheduled_at, repeat_value, repeat_unit, created_at, updated_at, deleted_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                owner_id = excluded.owner_id,
                task_id = excluded.task_id,
                recurring_task_id = excluded.recurring_task_id,
                scheduled_at = excluded.scheduled_at,
                repeat_value = excluded.repeat_value,
                repeat_unit = excluded.repeat_unit,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at
            """,
            bindings: reminderBindings(reminder, ownerID: ownerID),
            on: databaseHandle
        )
    }

    private func loadReminders(ownerID: String) -> [EntityReminder] {
        (try? database.query(
            """
            SELECT id, task_id, recurring_task_id, scheduled_at, repeat_value, repeat_unit, created_at, updated_at, deleted_at
            FROM reminders
            WHERE owner_id = ?
            ORDER BY scheduled_at ASC, id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            EntityReminder(
                id: RecordID(SQLiteColumn.text(row, index: 0)),
                taskId: SQLiteColumn.optionalText(row, index: 1).map { RecordID($0) },
                recurringTaskId: SQLiteColumn.optionalText(row, index: 2).map { RecordID($0) },
                scheduledAt: SQLiteColumn.date(row, index: 3),
                recurrence: recurrence(
                    repeatValue: SQLiteColumn.optionalInt(row, index: 4),
                    repeatUnit: SQLiteColumn.optionalText(row, index: 5)
                ),
                createdAt: SQLiteColumn.date(row, index: 6),
                updatedAt: SQLiteColumn.date(row, index: 7),
                deletedAt: SQLiteColumn.optionalDate(row, index: 8)
            )
        }) ?? []
    }

    func allReminderIDs() -> [RecordID] {
        (try? database.query(
            "SELECT id FROM reminders",
            at: databaseURL
        ) { row in
            RecordID(SQLiteColumn.text(row, index: 0))
        }) ?? []
    }

    private func replaceRows(
        ownerID: String,
        reminders: [EntityReminder],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try database.execute(
            "DELETE FROM reminders WHERE owner_id = ?",
            bindings: [.text(ownerID)],
            on: databaseHandle
        )

        for reminder in reminders {
            try database.execute(
                """
                INSERT INTO reminders (
                    id, owner_id, task_id, recurring_task_id, scheduled_at, repeat_value, repeat_unit, created_at, updated_at, deleted_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: reminderBindings(reminder, ownerID: ownerID),
                on: databaseHandle
            )
        }
    }

    private func reminderBindings(_ reminder: EntityReminder, ownerID: String) -> [SQLiteValue] {
        [
            .text(reminder.id.rawValue),
            .text(ownerID),
            reminder.taskId.map { .text($0.rawValue) } ?? .null,
            reminder.recurringTaskId.map { .text($0.rawValue) } ?? .null,
            .double(reminder.scheduledAt.timeIntervalSince1970),
            reminder.recurrence.map { .int(Int64($0.intervalValue)) } ?? .null,
            reminder.recurrence.map { .text($0.unit.rawValue) } ?? .null,
            .double(reminder.createdAt.timeIntervalSince1970),
            .double(reminder.updatedAt.timeIntervalSince1970),
            reminder.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null
        ]
    }

    private func sortReminders(_ lhs: EntityReminder, _ rhs: EntityReminder) -> Bool {
        if lhs.scheduledAt == rhs.scheduledAt {
            return lhs.id.rawValue < rhs.id.rawValue
        }

        return lhs.scheduledAt < rhs.scheduledAt
    }

    private func recurrence(repeatValue: Int?, repeatUnit: String?) -> ReminderRecurrence? {
        guard let repeatValue,
              let repeatUnit,
              let unit = ReminderRepeatUnit(rawValue: repeatUnit) else {
            return nil
        }

        let recurrence = ReminderRecurrence(intervalValue: repeatValue, unit: unit)
        return recurrence.isValid ? recurrence : nil
    }

}
