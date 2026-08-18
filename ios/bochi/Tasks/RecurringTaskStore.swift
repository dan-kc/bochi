import Foundation

// Sync flow: signed-in recurring task edits mark records dirty and publish
// mutations; server replacements refresh the store without re-triggering sync.
@Observable
@MainActor
final class RecurringTaskStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore

    private(set) var currentOwnerID: String
    private(set) var recurringTasks: [RecurringTask] = []

    var activeRecurringTasks: [RecurringTask] {
        recurringTasks.filter { $0.deletedAt == nil }
    }

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.syncStateStore = SyncStateStore(storageURL: self.databaseURL)
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        self.recurringTasks = loadRecurringTasks(ownerID: initialOwnerID)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        recurringTasks = loadRecurringTasks(ownerID: ownerID)
    }

    func migrateRecurringTasks(from sourceOwnerID: String, to destinationOwnerID: String) -> [RecordID] {
        guard sourceOwnerID != destinationOwnerID else { return [] }
        do {
            let migratedIDs = try database.transaction(at: databaseURL) { db in
                try self.migrateRecurringTasks(from: sourceOwnerID, to: destinationOwnerID, on: db)
            }
            refreshCurrentRecurringTasks()
            return migratedIDs
        } catch {
            assertionFailure("Failed to migrate recurringTasks: \(error)")
            return []
        }
    }

    @discardableResult
    func addRecurringTask(
        id: RecordID? = nil,
        name: String,
        description: String = "",
        frequency: Double? = nil,
        lockoutDurationSeconds: Int? = nil,
        basePrice: Int = 100,
        pinned: Bool = false,
        hidden: Bool = false,
        timerSelection: EntityTimerSelection = .none,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) -> RecurringTask? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else {
            return nil
        }

        let canonicalID = id ?? RecordID()
        let now = Date()
        let recurringTask = RecurringTask(
            id: canonicalID,
            name: trimmedName,
            description: description,
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deletedAt: deletedAt,
            frequency: frequency,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: max(0, basePrice),
            pinned: pinned,
            hidden: hidden,
            timerSelection: timerSelection
        )

        upsert(recurringTask, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(ids: [recurringTask.id])
        }
        return recurringTask
    }

    func deleteRecurringTask(id: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        guard let existing = recurringTasks.first(where: { $0.id == id }) else { return }
        let deleted = RecurringTask(
            id: existing.id,
            name: existing.name,
            description: existing.description,
            createdAt: existing.createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt,
            frequency: existing.frequency,
            lockoutDurationSeconds: existing.lockoutDurationSeconds,
            basePrice: existing.basePrice,
            pinned: existing.pinned,
            hidden: existing.hidden,
            timerSelection: existing.timerSelection,
            serverRevision: existing.serverRevision
        )

        upsert(deleted, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(ids: [id])
        }
    }

    func updateRecurringTask(
        id: RecordID,
        name: String? = nil,
        description: String? = nil,
        frequency: Double?? = nil,
        lockoutDurationSeconds: Int?? = nil,
        basePrice: Int? = nil,
        pinned: Bool? = nil,
        hidden: Bool? = nil,
        timerSelection: EntityTimerSelection? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date?? = nil,
        shouldNotifySync: Bool = true
    ) {
        guard let existing = recurringTasks.first(where: { $0.id == id }) else { return }

        let newName: String
        if let name = name {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && trimmed.count <= 100 {
                newName = trimmed
            } else {
                newName = existing.name
            }
        } else {
            newName = existing.name
        }

        let updated = RecurringTask(
            id: existing.id,
            name: newName,
            description: description ?? existing.description,
            createdAt: existing.createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt ?? existing.deletedAt,
            frequency: frequency ?? existing.frequency,
            lockoutDurationSeconds: lockoutDurationSeconds ?? existing.lockoutDurationSeconds,
            basePrice: basePrice.map { max(0, $0) } ?? existing.basePrice,
            pinned: pinned ?? existing.pinned,
            hidden: hidden ?? existing.hidden,
            timerSelection: timerSelection ?? existing.timerSelection,
            serverRevision: existing.serverRevision
        )

        upsert(updated, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(ids: [id])
        }
    }

    func setPinned(id: RecordID, pinned: Bool, updatedAt: Date = Date(), shouldNotifySync: Bool = true) {
        updateRecurringTask(
            id: id,
            pinned: pinned,
            updatedAt: updatedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func setHidden(id: RecordID, hidden: Bool, updatedAt: Date = Date(), shouldNotifySync: Bool = true) {
        updateRecurringTask(
            id: id,
            hidden: hidden,
            updatedAt: updatedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func mergeRecurringTasks(_ remoteRecurringTasks: [RecurringTask]) {
        guard !remoteRecurringTasks.isEmpty else { return }
        let merged = OwnerScopedRecordSupport.mergeRecords(local: recurringTasks, remote: remoteRecurringTasks)
        replaceRecurringTasks(merged)
    }

    func replaceRecurringTasks(_ authoritativeRecurringTasks: [RecurringTask]) {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeRecurringTasks)
        do {
            try persistReplacedRecurringTasks(sorted)
        } catch {
            assertionFailure("Failed to replace recurringTasks: \(error)")
            return
        }
    }

    func persistServerRevisions(_ revisionsByID: [RecordID: Int64]) throws {
        guard !revisionsByID.isEmpty else { return }
        let updated = recurringTasks.map { recurringTask in
            guard let serverRevision = revisionsByID[recurringTask.id] else { return recurringTask }
            return RecurringTask(
                id: recurringTask.id,
                name: recurringTask.name,
                description: recurringTask.description,
                createdAt: recurringTask.createdAt,
                updatedAt: recurringTask.updatedAt,
                deletedAt: recurringTask.deletedAt,
                frequency: recurringTask.frequency,
                lockoutDurationSeconds: recurringTask.lockoutDurationSeconds,
                basePrice: recurringTask.basePrice,
                pinned: recurringTask.pinned,
                hidden: recurringTask.hidden,
                timerSelection: recurringTask.timerSelection,
                serverRevision: serverRevision
            )
        }
        try persistReplacedRecurringTasks(updated)
    }

    func getDirtyRecurringTasks(ids: Set<RecordID>) -> [RecurringTask] {
        recurringTasks.filter { ids.contains($0.id) }
    }

    func purgeDeletedRecurringTasks(excluding dirtyIDs: Set<RecordID> = []) {
        do {
            try persistDeletedRecurringTaskPurge(excluding: dirtyIDs)
        } catch {
            assertionFailure("Failed to purge deleted recurringTasks: \(error)")
            return
        }
    }

    func allRecurringTaskIDs() -> [RecordID] {
        recurringTasks.map(\.id)
    }

    func migrateRecurringTasks(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> [RecordID] {
        guard sourceOwnerID != destinationOwnerID else { return [] }
        let source = loadRecurringTasks(ownerID: sourceOwnerID)
        let destination = loadRecurringTasks(ownerID: destinationOwnerID)
        let merged = OwnerScopedRecordSupport.mergeRecords(local: destination, remote: source)

        // Remove the local-owner rows before re-inserting the merged account view
        // so a sign-in migration does not trip the global recurringTask-id uniqueness rule.
        try replaceRows(ownerID: sourceOwnerID, recurringTasks: [], on: databaseHandle)
        try replaceRows(ownerID: destinationOwnerID, recurringTasks: merged, on: databaseHandle)
        return source.map(\.id)
    }

    func persistReplacedRecurringTasks(_ authoritativeRecurringTasks: [RecurringTask]) throws {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeRecurringTasks)
        try database.transaction(at: databaseURL) { db in
            try self.replaceRows(ownerID: self.currentOwnerID, recurringTasks: sorted, on: db)
        }
        recurringTasks = sorted
    }

    func replaceRecurringTasks(
        _ authoritativeRecurringTasks: [RecurringTask],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeRecurringTasks)
        try replaceRows(ownerID: currentOwnerID, recurringTasks: sorted, on: databaseHandle)
    }

    func persistDeletedRecurringTaskPurge(excluding dirtyIDs: Set<RecordID>) throws {
        try database.transaction(at: databaseURL) { db in
            try self.purgeDeletedRecurringTasks(excluding: dirtyIDs, on: db)
        }
        refreshCurrentRecurringTasks()
    }

    func purgeDeletedRecurringTasks(
        excluding dirtyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        if dirtyIDs.isEmpty {
            try database.execute(
                "DELETE FROM tasks WHERE owner_id = ? AND recurring = TRUE AND deleted_at IS NOT NULL",
                bindings: [.text(currentOwnerID)],
                on: databaseHandle
            )
            return
        }

        let placeholders = Array(repeating: "?", count: dirtyIDs.count).joined(separator: ", ")
        let bindings: [SQLiteValue] = [SQLiteValue.text(currentOwnerID)]
            + dirtyIDs.sorted { $0.rawValue < $1.rawValue }.map { SQLiteValue.text($0.rawValue) }
        try database.execute(
            "DELETE FROM tasks WHERE owner_id = ? AND recurring = TRUE AND deleted_at IS NOT NULL AND id NOT IN (\(placeholders))",
            bindings: bindings,
            on: databaseHandle
        )
    }

    private func upsert(_ recurringTask: RecurringTask, markDirty: Bool) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.upsert(recurringTask, on: db)
                if markDirty, self.currentOwnerID != StorageOwner.local {
                    try self.syncStateStore.markDirty(userID: self.currentOwnerID, kind: .recurringTasks, ids: [recurringTask.id], on: db)
                }
            }
        } catch {
            assertionFailure("Failed to upsert recurringTask: \(error)")
            return
        }
        refreshCurrentRecurringTasks()
    }

    private func upsert(_ recurringTask: RecurringTask, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO tasks (
                id, owner_id, recurring, name, description, created_at, updated_at, deleted_at,
                base_price, due_date,
                min_daily_frequency, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id,
                server_revision
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                owner_id = excluded.owner_id,
                recurring = excluded.recurring,
                name = excluded.name,
                description = excluded.description,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                base_price = excluded.base_price,
                due_date = excluded.due_date,
                min_daily_frequency = excluded.min_daily_frequency,
                lockout_duration_seconds = excluded.lockout_duration_seconds,
                pinned = excluded.pinned,
                hidden = excluded.hidden,
                timer_mode = excluded.timer_mode,
                timer_id = excluded.timer_id,
                server_revision = excluded.server_revision
            """,
            bindings: recurringTaskBindings(recurringTask, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func upsert(_ recurringTask: RecurringTask, ownerID: String, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO tasks (
                id, owner_id, recurring, name, description, created_at, updated_at, deleted_at,
                base_price, due_date,
                min_daily_frequency, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id,
                server_revision
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                owner_id = excluded.owner_id,
                recurring = excluded.recurring,
                name = excluded.name,
                description = excluded.description,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                base_price = excluded.base_price,
                due_date = excluded.due_date,
                min_daily_frequency = excluded.min_daily_frequency,
                lockout_duration_seconds = excluded.lockout_duration_seconds,
                pinned = excluded.pinned,
                hidden = excluded.hidden,
                timer_mode = excluded.timer_mode,
                timer_id = excluded.timer_id,
                server_revision = excluded.server_revision
            """,
            bindings: recurringTaskBindings(recurringTask, ownerID: ownerID),
            on: databaseHandle
        )
    }

    private func loadRecurringTasks(ownerID: String) -> [RecurringTask] {
        let fetched = (try? database.query(
            """
            SELECT id, name, description, created_at, updated_at, deleted_at,
                   min_daily_frequency, base_price,
                   lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision
            FROM tasks
            WHERE owner_id = ? AND recurring = TRUE
            ORDER BY created_at ASC, id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            RecurringTask(
                id: RecordID(SQLiteColumn.text(row, index: 0)),
                name: SQLiteColumn.text(row, index: 1),
                description: SQLiteColumn.text(row, index: 2),
                createdAt: SQLiteColumn.date(row, index: 3),
                updatedAt: SQLiteColumn.date(row, index: 4),
                deletedAt: SQLiteColumn.optionalDate(row, index: 5),
                frequency: SQLiteColumn.optionalDouble(row, index: 6),
                lockoutDurationSeconds: SQLiteColumn.optionalInt(row, index: 8),
                basePrice: SQLiteColumn.int(row, index: 7),
                pinned: SQLiteColumn.bool(row, index: 9),
                hidden: SQLiteColumn.bool(row, index: 10),
                timerSelection: EntityTimerSelection.from(
                    mode: SQLiteColumn.optionalText(row, index: 11),
                    timerID: SQLiteColumn.optionalText(row, index: 12).map { RecordID($0) }
                ),
                serverRevision: SQLiteColumn.optionalInt64(row, index: 13)
            )
        }) ?? []

        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func refreshCurrentRecurringTasks() {
        recurringTasks = loadRecurringTasks(ownerID: currentOwnerID)
    }

    private func replaceRows(ownerID: String, recurringTasks: [RecurringTask], on databaseHandle: AppDatabaseHandle) throws {
        // Full sync gives us an authoritative owner snapshot. Delete only rows
        // missing from that snapshot, then upsert changed/current rows.
        try database.execute(
            "CREATE TEMP TABLE IF NOT EXISTS recurringTask_replacement_ids (id TEXT PRIMARY KEY)",
            on: databaseHandle
        )
        try database.execute(
            "DELETE FROM recurringTask_replacement_ids",
            on: databaseHandle
        )
        for recurringTask in recurringTasks {
            try database.execute(
                "INSERT OR IGNORE INTO recurringTask_replacement_ids (id) VALUES (?)",
                bindings: [.text(recurringTask.id.rawValue)],
                on: databaseHandle
            )
        }
        try database.execute(
            """
            DELETE FROM tasks
            WHERE owner_id = ? AND recurring = TRUE
              AND NOT EXISTS (
                  SELECT 1 FROM recurringTask_replacement_ids replacement
                  WHERE replacement.id = tasks.id
              )
            """,
            bindings: [.text(ownerID)],
            on: databaseHandle
        )

        for recurringTask in recurringTasks {
            try upsert(recurringTask, ownerID: ownerID, on: databaseHandle)
        }
        try database.execute("DELETE FROM recurringTask_replacement_ids", on: databaseHandle)
    }

    private func recurringTaskBindings(_ recurringTask: RecurringTask, ownerID: String) -> [SQLiteValue] {
        [
            .text(recurringTask.id.rawValue),
            .text(ownerID),
            .int(1),
            .text(recurringTask.name),
            .text(recurringTask.description),
            .double(recurringTask.createdAt.timeIntervalSince1970),
            .double(recurringTask.updatedAt.timeIntervalSince1970),
            recurringTask.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            .int(Int64(recurringTask.basePrice)),
            .null,
            recurringTask.frequency.map(SQLiteValue.double) ?? .null,
            recurringTask.lockoutDurationSeconds.map { .int(Int64($0)) } ?? .null,
            .int(recurringTask.pinned ? 1 : 0),
            .int(recurringTask.hidden ? 1 : 0),
            recurringTask.timerSelection.modeValue.map { .text($0) } ?? .null,
            recurringTask.timerSelection.timerID.map { .text($0.rawValue) } ?? .null,
            recurringTask.serverRevision.map { .int($0) } ?? .null
        ]
    }

    private func notifySync(ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .recurringTasks, recordIDs: ids))
    }
}
