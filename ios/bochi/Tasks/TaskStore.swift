import Foundation

// Sync flow: signed-in task edits mark records dirty and publish mutations;
// server replacements refresh the store without enqueueing another sync.
@Observable
@MainActor
final class TaskStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore

    private(set) var currentOwnerID: String
    private(set) var tasks: [TaskItem] = []

    var activeTasks: [TaskItem] {
        tasks.filter { $0.deletedAt == nil }
    }

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.syncStateStore = SyncStateStore(storageURL: self.databaseURL)
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        self.tasks = loadTasks(ownerID: initialOwnerID)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        tasks = loadTasks(ownerID: ownerID)
    }

    func migrateTasks(from sourceOwnerID: String, to destinationOwnerID: String) -> [RecordID] {
        guard sourceOwnerID != destinationOwnerID else { return [] }
        do {
            let migratedIDs = try database.transaction(at: databaseURL) { db in
                try self.migrateTasks(from: sourceOwnerID, to: destinationOwnerID, on: db)
            }
            refreshCurrentTasks()
            return migratedIDs
        } catch {
            assertionFailure("Failed to migrate tasks: \(error)")
            return []
        }
    }

    @discardableResult
    func addTask(
        id: RecordID? = nil,
        name: String,
        description: String = "",
        basePrice: Int = 200,
        dueDate: Date? = nil,
        pinned: Bool = false,
        hidden: Bool = false,
        timerSelection: EntityTimerSelection = .none,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) -> TaskItem? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else {
            return nil
        }

        let canonicalID = id ?? RecordID()
        let now = Date()
        let task = TaskItem(
            id: canonicalID,
            name: trimmedName,
            description: description,
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deletedAt: deletedAt,
            basePrice: max(0, basePrice),
            dueDate: dueDate,
            pinned: pinned,
            hidden: hidden,
            timerSelection: timerSelection
        )

        upsert(task, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(ids: [task.id])
        }
        return task
    }

    func updateTask(
        id: RecordID,
        name: String? = nil,
        description: String? = nil,
        basePrice: Int? = nil,
        dueDate: Date?? = nil,
        pinned: Bool? = nil,
        hidden: Bool? = nil,
        timerSelection: EntityTimerSelection? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date?? = nil,
        shouldNotifySync: Bool = true
    ) {
        guard let existing = tasks.first(where: { $0.id == id }) else { return }

        let newName: String
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && trimmed.count <= 100 {
                newName = trimmed
            } else {
                newName = existing.name
            }
        } else {
            newName = existing.name
        }

        let updated = TaskItem(
            id: existing.id,
            name: newName,
            description: description ?? existing.description,
            createdAt: existing.createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt ?? existing.deletedAt,
            basePrice: basePrice.map { max(0, $0) } ?? existing.basePrice,
            dueDate: dueDate ?? existing.dueDate,
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

    func deleteTask(id: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        updateTask(
            id: id,
            updatedAt: deletedAt,
            deletedAt: .some(deletedAt),
            shouldNotifySync: shouldNotifySync
        )
    }

    func setPinned(id: RecordID, pinned: Bool, updatedAt: Date = Date(), shouldNotifySync: Bool = true) {
        updateTask(
            id: id,
            pinned: pinned,
            updatedAt: updatedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func setHidden(id: RecordID, hidden: Bool, updatedAt: Date = Date(), shouldNotifySync: Bool = true) {
        updateTask(
            id: id,
            hidden: hidden,
            updatedAt: updatedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func mergeTasks(_ remoteTasks: [TaskItem]) {
        guard !remoteTasks.isEmpty else { return }
        replaceTasks(OwnerScopedRecordSupport.mergeRecords(local: tasks, remote: remoteTasks))
    }

    func replaceTasks(_ authoritativeTasks: [TaskItem]) {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeTasks)
        do {
            try persistReplacedTasks(sorted)
        } catch {
            assertionFailure("Failed to replace tasks: \(error)")
            return
        }
    }

    func persistServerRevisions(_ revisionsByID: [RecordID: Int64]) throws {
        guard !revisionsByID.isEmpty else { return }
        let updated = tasks.map { task in
            guard let serverRevision = revisionsByID[task.id] else { return task }
            return TaskItem(
                id: task.id,
                name: task.name,
                description: task.description,
                createdAt: task.createdAt,
                updatedAt: task.updatedAt,
                deletedAt: task.deletedAt,
                basePrice: task.basePrice,
                dueDate: task.dueDate,
                pinned: task.pinned,
                hidden: task.hidden,
                timerSelection: task.timerSelection,
                serverRevision: serverRevision
            )
        }
        try persistReplacedTasks(updated)
    }

    func getDirtyTasks(ids: Set<RecordID>) -> [TaskItem] {
        tasks.filter { ids.contains($0.id) }
    }

    func purgeDeletedTasks(excluding dirtyIDs: Set<RecordID> = []) {
        do {
            try persistDeletedTaskPurge(excluding: dirtyIDs)
        } catch {
            assertionFailure("Failed to purge deleted tasks: \(error)")
            return
        }
    }

    func allTaskIDs() -> [RecordID] {
        tasks.map(\.id)
    }

    func migrateTasks(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> [RecordID] {
        guard sourceOwnerID != destinationOwnerID else { return [] }
        let source = loadTasks(ownerID: sourceOwnerID)
        let destination = loadTasks(ownerID: destinationOwnerID)
        let merged = OwnerScopedRecordSupport.mergeRecords(local: destination, remote: source)

        try replaceRows(ownerID: sourceOwnerID, tasks: [], on: databaseHandle)
        try replaceRows(ownerID: destinationOwnerID, tasks: merged, on: databaseHandle)
        return source.map(\.id)
    }

    func persistReplacedTasks(_ authoritativeTasks: [TaskItem]) throws {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeTasks)
        try database.transaction(at: databaseURL) { db in
            try self.replaceRows(ownerID: self.currentOwnerID, tasks: sorted, on: db)
        }
        tasks = sorted
    }

    func replaceTasks(
        _ authoritativeTasks: [TaskItem],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeTasks)
        try replaceRows(ownerID: currentOwnerID, tasks: sorted, on: databaseHandle)
    }

    func persistDeletedTaskPurge(excluding dirtyIDs: Set<RecordID>) throws {
        try database.transaction(at: databaseURL) { db in
            try self.purgeDeletedTasks(excluding: dirtyIDs, on: db)
        }
        refreshCurrentTasks()
    }

    func purgeDeletedTasks(
        excluding dirtyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        if dirtyIDs.isEmpty {
            try database.execute(
                "DELETE FROM tasks WHERE owner_id = ? AND recurring = FALSE AND deleted_at IS NOT NULL",
                bindings: [.text(currentOwnerID)],
                on: databaseHandle
            )
            return
        }

        let placeholders = Array(repeating: "?", count: dirtyIDs.count).joined(separator: ", ")
        let bindings: [SQLiteValue] = [SQLiteValue.text(currentOwnerID)]
            + dirtyIDs.sorted { $0.rawValue < $1.rawValue }.map { SQLiteValue.text($0.rawValue) }
        try database.execute(
            "DELETE FROM tasks WHERE owner_id = ? AND recurring = FALSE AND deleted_at IS NOT NULL AND id NOT IN (\(placeholders))",
            bindings: bindings,
            on: databaseHandle
        )
    }

    private func upsert(_ task: TaskItem, markDirty: Bool) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.upsert(task, on: db)
                if markDirty, self.currentOwnerID != StorageOwner.local {
                    try self.syncStateStore.markDirty(userID: self.currentOwnerID, kind: .tasks, ids: [task.id], on: db)
                }
            }
        } catch {
            assertionFailure("Failed to upsert task: \(error)")
            return
        }
        refreshCurrentTasks()
    }

    private func upsert(_ task: TaskItem, on databaseHandle: AppDatabaseHandle) throws {
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
            bindings: taskBindings(task, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func upsert(_ task: TaskItem, ownerID: String, on databaseHandle: AppDatabaseHandle) throws {
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
            bindings: taskBindings(task, ownerID: ownerID),
            on: databaseHandle
        )
    }

    private func loadTasks(ownerID: String) -> [TaskItem] {
        let fetched = (try? database.query(
            """
            SELECT
                id, name, description, created_at, updated_at, deleted_at,
                base_price, due_date, pinned, hidden, timer_mode, timer_id, server_revision
            FROM tasks
            WHERE owner_id = ? AND recurring = FALSE
            ORDER BY created_at ASC, id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            TaskItem(
                id: RecordID(SQLiteColumn.text(row, index: 0)),
                name: SQLiteColumn.text(row, index: 1),
                description: SQLiteColumn.text(row, index: 2),
                createdAt: SQLiteColumn.date(row, index: 3),
                updatedAt: SQLiteColumn.date(row, index: 4),
                deletedAt: SQLiteColumn.optionalDate(row, index: 5),
                basePrice: SQLiteColumn.int(row, index: 6),
                dueDate: SQLiteColumn.optionalDate(row, index: 7),
                pinned: SQLiteColumn.bool(row, index: 8),
                hidden: SQLiteColumn.bool(row, index: 9),
                timerSelection: EntityTimerSelection.from(
                    mode: SQLiteColumn.optionalText(row, index: 10),
                    timerID: SQLiteColumn.optionalText(row, index: 11).map { RecordID($0) }
                ),
                serverRevision: SQLiteColumn.optionalInt64(row, index: 12)
            )
        }) ?? []
        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func refreshCurrentTasks() {
        tasks = loadTasks(ownerID: currentOwnerID)
    }

    private func replaceRows(
        ownerID: String,
        tasks: [TaskItem],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        // Full sync gives us an authoritative owner snapshot. Delete only rows
        // missing from that snapshot, then upsert changed/current rows.
        try database.execute(
            "CREATE TEMP TABLE IF NOT EXISTS task_replacement_ids (id TEXT PRIMARY KEY)",
            on: databaseHandle
        )
        try database.execute(
            "DELETE FROM task_replacement_ids",
            on: databaseHandle
        )
        for task in tasks {
            try database.execute(
                "INSERT OR IGNORE INTO task_replacement_ids (id) VALUES (?)",
                bindings: [.text(task.id.rawValue)],
                on: databaseHandle
            )
        }
        try database.execute(
            """
            DELETE FROM tasks
            WHERE owner_id = ? AND recurring = FALSE
              AND NOT EXISTS (
                  SELECT 1 FROM task_replacement_ids replacement
                  WHERE replacement.id = tasks.id
              )
            """,
            bindings: [.text(ownerID)],
            on: databaseHandle
        )

        for task in tasks {
            try upsert(task, ownerID: ownerID, on: databaseHandle)
        }
        try database.execute("DELETE FROM task_replacement_ids", on: databaseHandle)
    }

    private func taskBindings(_ task: TaskItem, ownerID: String) -> [SQLiteValue] {
        [
            .text(task.id.rawValue),
            .text(ownerID),
            .int(0),
            .text(task.name),
            .text(task.description),
            .double(task.createdAt.timeIntervalSince1970),
            .double(task.updatedAt.timeIntervalSince1970),
            task.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            .int(Int64(task.basePrice)),
            task.dueDate.map { .double($0.timeIntervalSince1970) } ?? .null,
            .null,
            .null,
            .int(task.pinned ? 1 : 0),
            .int(task.hidden ? 1 : 0),
            task.timerSelection.modeValue.map { .text($0) } ?? .null,
            task.timerSelection.timerID.map { .text($0.rawValue) } ?? .null,
            task.serverRevision.map { .int($0) } ?? .null
        ]
    }

    private func notifySync(ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .tasks, recordIDs: ids))
    }
}
