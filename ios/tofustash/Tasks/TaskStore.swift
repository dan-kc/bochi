import Foundation

@Observable
@MainActor
final class TaskStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore

    private(set) var currentOwnerID: String
    private(set) var tasks: [TaskItem] = []

    var activeTasks: [TaskItem] {
        tasks.filter { $0.deletedAt == nil && $0.completedAt == nil }
    }

    var completedTasks: [TaskItem] {
        tasks.filter { $0.deletedAt == nil && $0.completedAt != nil }
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
        difficultyTier: HabitDifficultyTier? = nil,
        durationSeconds: Int? = nil,
        skipConsequence: Int? = nil,
        dueDate: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        completedAt: Date? = nil,
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
            completedAt: completedAt,
            difficultyTier: difficultyTier,
            durationSeconds: durationSeconds,
            skipConsequence: skipConsequence,
            dueDate: dueDate
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
        difficultyTier: HabitDifficultyTier?? = nil,
        durationSeconds: Int?? = nil,
        skipConsequence: Int?? = nil,
        dueDate: Date?? = nil,
        completedAt: Date?? = nil,
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
            completedAt: completedAt ?? existing.completedAt,
            difficultyTier: difficultyTier ?? existing.difficultyTier,
            durationSeconds: durationSeconds ?? existing.durationSeconds,
            skipConsequence: skipConsequence ?? existing.skipConsequence,
            dueDate: dueDate ?? existing.dueDate
        )

        upsert(updated, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(ids: [id])
        }
    }

    func completeTask(
        id: RecordID,
        completedAt: Date = Date(),
        shouldNotifySync: Bool = true
    ) {
        updateTask(
            id: id,
            completedAt: .some(completedAt),
            updatedAt: completedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func deleteTask(id: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        updateTask(
            id: id,
            updatedAt: deletedAt,
            deletedAt: .some(deletedAt),
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
                "DELETE FROM tasks WHERE owner_id = ? AND deleted_at IS NOT NULL",
                bindings: [.text(currentOwnerID)],
                on: databaseHandle
            )
            return
        }

        let placeholders = Array(repeating: "?", count: dirtyIDs.count).joined(separator: ", ")
        let bindings: [SQLiteValue] = [SQLiteValue.text(currentOwnerID)]
            + dirtyIDs.sorted { $0.rawValue < $1.rawValue }.map { SQLiteValue.text($0.rawValue) }
        try database.execute(
            "DELETE FROM tasks WHERE owner_id = ? AND deleted_at IS NOT NULL AND id NOT IN (\(placeholders))",
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
                id, owner_id, name, description, created_at, updated_at, deleted_at, completed_at,
                difficulty_tier, duration_seconds, skip_consequence, due_date
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                owner_id = excluded.owner_id,
                name = excluded.name,
                description = excluded.description,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                completed_at = excluded.completed_at,
                difficulty_tier = excluded.difficulty_tier,
                duration_seconds = excluded.duration_seconds,
                skip_consequence = excluded.skip_consequence,
                due_date = excluded.due_date
            """,
            bindings: taskBindings(task, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func loadTasks(ownerID: String) -> [TaskItem] {
        let fetched = (try? database.query(
            """
            SELECT
                id, name, description, created_at, updated_at, deleted_at, completed_at,
                difficulty_tier, duration_seconds, skip_consequence, due_date
            FROM tasks
            WHERE owner_id = ?
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
                completedAt: SQLiteColumn.optionalDate(row, index: 6),
                difficultyTier: SQLiteColumn.optionalText(row, index: 7).flatMap(HabitDifficultyTier.init(rawValue:)),
                durationSeconds: SQLiteColumn.optionalInt(row, index: 8),
                skipConsequence: SQLiteColumn.optionalInt(row, index: 9),
                dueDate: SQLiteColumn.optionalDate(row, index: 10)
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
        try database.execute(
            "DELETE FROM tasks WHERE owner_id = ?",
            bindings: [.text(ownerID)],
            on: databaseHandle
        )

        for task in tasks {
            try database.execute(
                """
                INSERT INTO tasks (
                    id, owner_id, name, description, created_at, updated_at, deleted_at, completed_at,
                    difficulty_tier, duration_seconds, skip_consequence, due_date
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: taskBindings(task, ownerID: ownerID),
                on: databaseHandle
            )
        }
    }

    private func taskBindings(_ task: TaskItem, ownerID: String) -> [SQLiteValue] {
        [
            .text(task.id.rawValue),
            .text(ownerID),
            .text(task.name),
            .text(task.description),
            .double(task.createdAt.timeIntervalSince1970),
            .double(task.updatedAt.timeIntervalSince1970),
            task.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            task.completedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            task.difficultyTier.map { .text($0.rawValue) } ?? .null,
            task.durationSeconds.map { .int(Int64($0)) } ?? .null,
            task.skipConsequence.map { .int(Int64($0)) } ?? .null,
            task.dueDate.map { .double($0.timeIntervalSince1970) } ?? .null
        ]
    }

    private func notifySync(ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .tasks, recordIDs: ids))
    }
}
