import Foundation

// Sync flow: dependency edits mark graph link rows dirty and publish mutations;
// sync replacement methods refresh links without enqueueing another sync.
@Observable
@MainActor
final class TaskDependencyStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore

    private(set) var currentOwnerID: String
    private(set) var taskTaskDependencies: [TaskTaskDependency] = []
    private(set) var taskRecurringTaskDependencies: [TaskRecurringTaskDependency] = []

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.syncStateStore = SyncStateStore(storageURL: self.databaseURL)
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        refreshAll()
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        refreshAll()
    }

    func migrateDependencies(
        from sourceOwnerID: String,
        to destinationOwnerID: String
    ) -> (taskTaskDependencyIDs: [RecordID], taskRecurringTaskDependencyIDs: [RecordID]) {
        guard sourceOwnerID != destinationOwnerID else { return ([], []) }

        do {
            let result = try database.transaction(at: databaseURL) { db in
                try self.migrateDependencies(from: sourceOwnerID, to: destinationOwnerID, on: db)
            }
            refreshAll()
            return result
        } catch {
            assertionFailure("Failed to migrate task dependencies: \(error)")
            return ([], [])
        }
    }

    func migrateDependencies(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> (taskTaskDependencyIDs: [RecordID], taskRecurringTaskDependencyIDs: [RecordID]) {
        guard sourceOwnerID != destinationOwnerID else { return ([], []) }

        let sourceTaskTaskDependencies = loadTaskTaskDependencies(ownerID: sourceOwnerID)
        let sourceTaskRecurringTaskDependencies = loadTaskRecurringTaskDependencies(ownerID: sourceOwnerID)
        let destinationTaskTaskDependencies = loadTaskTaskDependencies(ownerID: destinationOwnerID)
        let destinationTaskRecurringTaskDependencies = loadTaskRecurringTaskDependencies(ownerID: destinationOwnerID)

        let mergedTaskTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: destinationTaskTaskDependencies,
            remote: sourceTaskTaskDependencies
        )
        let mergedTaskRecurringTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: destinationTaskRecurringTaskDependencies,
            remote: sourceTaskRecurringTaskDependencies
        )

        try replaceRows(
            ownerID: sourceOwnerID,
            taskTaskDependencies: [],
            taskRecurringTaskDependencies: [],
            on: databaseHandle
        )
        try replaceRows(
            ownerID: destinationOwnerID,
            taskTaskDependencies: mergedTaskTaskDependencies,
            taskRecurringTaskDependencies: mergedTaskRecurringTaskDependencies,
            on: databaseHandle
        )

        return (
            taskTaskDependencyIDs: sourceTaskTaskDependencies.map(\.id),
            taskRecurringTaskDependencyIDs: sourceTaskRecurringTaskDependencies.map(\.id)
        )
    }

    func activeTaskDependencies(for taskID: RecordID) -> [TaskTaskDependency] {
        taskTaskDependencies.filter { $0.taskId == taskID && $0.deletedAt == nil }
    }

    func activeRecurringTaskDependencies(for taskID: RecordID) -> [TaskRecurringTaskDependency] {
        taskRecurringTaskDependencies.filter { $0.taskId == taskID && $0.deletedAt == nil }
    }

    func isTaskBlocked(
        _ task: TaskItem,
        taskStore: TaskStore,
        tradeStore: TradeStore,
        hasPremiumAccess: Bool = true
    ) -> Bool {
        guard hasPremiumAccess else { return false }
        guard task.deletedAt == nil else { return false }
        let latestTaskTradesByTaskID = tradeStore.latestUnrefundedTaskTradesByTaskID()
        guard latestTaskTradesByTaskID[task.id] == nil else { return false }

        if activeTaskDependencies(for: task.id).contains(where: { dependency in
            guard let prerequisiteTask = taskStore.tasks.first(where: { $0.id == dependency.dependsOnTaskId }) else {
                return false
            }
            guard prerequisiteTask.deletedAt == nil else { return false }
            return latestTaskTradesByTaskID[prerequisiteTask.id] == nil
        }) {
            return true
        }

        return activeRecurringTaskDependencies(for: task.id).contains { dependency in
            recurringTaskDependencyProgress(for: dependency, tradeStore: tradeStore) < dependency.requiredCompletions
        }
    }

    func recurringTaskDependencyProgress(
        for dependency: TaskRecurringTaskDependency,
        tradeStore: TradeStore
    ) -> Int {
        max(0, tradeStore.recurringTaskCompletionCount(recurringTaskId: dependency.recurringTaskId) - dependency.baselineCompletionCount)
    }

    func replaceDependencies(
        for taskID: RecordID,
        taskDependencies: [TaskTaskDependency],
        recurringTaskDependencies: [TaskRecurringTaskDependency],
        shouldNotifySync: Bool = true
    ) {
        let existingTaskDependenciesByID = Dictionary(uniqueKeysWithValues: taskTaskDependencies.map { ($0.id, $0) })
        let existingRecurringTaskDependenciesByID = Dictionary(uniqueKeysWithValues: taskRecurringTaskDependencies.map { ($0.id, $0) })
        let normalizedTaskDependencies = taskDependencies.map { dependency in
            normalizedTaskTaskDependency(dependency, existing: existingTaskDependenciesByID[dependency.id])
        }
        let normalizedRecurringTaskDependencies = recurringTaskDependencies.map { dependency in
            normalizedTaskRecurringTaskDependency(dependency, existing: existingRecurringTaskDependenciesByID[dependency.id])
        }

        let existingTaskDependencies = activeTaskDependencies(for: taskID)
        let existingRecurringTaskDependencies = activeRecurringTaskDependencies(for: taskID)
        let incomingTaskDependencyIDs = Set(normalizedTaskDependencies.map(\.id))
        let incomingRecurringTaskDependencyIDs = Set(normalizedRecurringTaskDependencies.map(\.id))

        let deletedTaskDependencies = existingTaskDependencies
            .filter { !incomingTaskDependencyIDs.contains($0.id) }
            .map {
                let updatedAt = nextUpdatedAt(after: $0.updatedAt)
                return TaskTaskDependency(
                    taskId: $0.taskId,
                    dependsOnTaskId: $0.dependsOnTaskId,
                    createdAt: $0.createdAt,
                    updatedAt: updatedAt,
                    deletedAt: updatedAt,
                    serverRevision: $0.serverRevision
                )
            }

        let deletedRecurringTaskDependencies = existingRecurringTaskDependencies
            .filter { !incomingRecurringTaskDependencyIDs.contains($0.id) }
            .map {
                let updatedAt = nextUpdatedAt(after: $0.updatedAt)
                return TaskRecurringTaskDependency(
                    taskId: $0.taskId,
                    recurringTaskId: $0.recurringTaskId,
                    requiredCompletions: $0.requiredCompletions,
                    baselineCompletionCount: $0.baselineCompletionCount,
                    createdAt: $0.createdAt,
                    updatedAt: updatedAt,
                    deletedAt: updatedAt,
                    serverRevision: $0.serverRevision
                )
            }

        let mergedTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: taskTaskDependencies,
            remote: normalizedTaskDependencies + deletedTaskDependencies
        )
        let mergedRecurringTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: taskRecurringTaskDependencies,
            remote: normalizedRecurringTaskDependencies + deletedRecurringTaskDependencies
        )

        do {
            try persistReplacedAll(
                taskTaskDependencies: mergedTaskDependencies,
                taskRecurringTaskDependencies: mergedRecurringTaskDependencies
            )
        } catch {
            assertionFailure("Failed to replace task dependencies: \(error)")
            return
        }

        guard shouldNotifySync else { return }

        let dirtyTaskTaskIDs = normalizedTaskDependencies.map(\.id) + deletedTaskDependencies.map(\.id)
        let dirtyTaskRecurringTaskIDs = normalizedRecurringTaskDependencies.map(\.id) + deletedRecurringTaskDependencies.map(\.id)

        markDirtyAndNotify(kind: .taskTaskDependencies, ids: dirtyTaskTaskIDs)
        markDirtyAndNotify(kind: .taskRecurringTaskDependencies, ids: dirtyTaskRecurringTaskIDs)
    }

    func deleteDependenciesReferencingTask(
        _ taskID: RecordID,
        deletedAt: Date = Date(),
        shouldNotifySync: Bool = true
    ) {
        let deletedTaskDependencies = taskTaskDependencies.compactMap { dependency -> TaskTaskDependency? in
            guard dependency.deletedAt == nil else { return nil }
            guard dependency.taskId == taskID || dependency.dependsOnTaskId == taskID else { return nil }

            let tombstoneAt = dependency.updatedAt < deletedAt
                ? deletedAt
                : nextUpdatedAt(after: dependency.updatedAt)
            return TaskTaskDependency(
                taskId: dependency.taskId,
                dependsOnTaskId: dependency.dependsOnTaskId,
                createdAt: dependency.createdAt,
                updatedAt: tombstoneAt,
                deletedAt: tombstoneAt,
                serverRevision: dependency.serverRevision
            )
        }

        let deletedRecurringTaskDependencies = taskRecurringTaskDependencies.compactMap { dependency -> TaskRecurringTaskDependency? in
            guard dependency.deletedAt == nil else { return nil }
            guard dependency.taskId == taskID else { return nil }

            let tombstoneAt = dependency.updatedAt < deletedAt
                ? deletedAt
                : nextUpdatedAt(after: dependency.updatedAt)
            return TaskRecurringTaskDependency(
                taskId: dependency.taskId,
                recurringTaskId: dependency.recurringTaskId,
                requiredCompletions: dependency.requiredCompletions,
                baselineCompletionCount: dependency.baselineCompletionCount,
                createdAt: dependency.createdAt,
                updatedAt: tombstoneAt,
                deletedAt: tombstoneAt,
                serverRevision: dependency.serverRevision
            )
        }

        guard !deletedTaskDependencies.isEmpty || !deletedRecurringTaskDependencies.isEmpty else { return }

        let mergedTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: taskTaskDependencies,
            remote: deletedTaskDependencies
        )
        let mergedRecurringTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: taskRecurringTaskDependencies,
            remote: deletedRecurringTaskDependencies
        )

        do {
            try persistReplacedAll(
                taskTaskDependencies: mergedTaskDependencies,
                taskRecurringTaskDependencies: mergedRecurringTaskDependencies
            )
        } catch {
            assertionFailure("Failed to delete task dependencies for task deletion: \(error)")
            return
        }

        guard shouldNotifySync else { return }

        let dirtyTaskTaskIDs = deletedTaskDependencies.map(\.id)
        let dirtyTaskRecurringTaskIDs = deletedRecurringTaskDependencies.map(\.id)

        markDirtyAndNotify(kind: .taskTaskDependencies, ids: dirtyTaskTaskIDs)
        markDirtyAndNotify(kind: .taskRecurringTaskDependencies, ids: dirtyTaskRecurringTaskIDs)
    }

    func deleteDependenciesReferencingRecurringTask(
        _ recurringTaskID: RecordID,
        deletedAt: Date = Date(),
        shouldNotifySync: Bool = true
    ) {
        let deletedRecurringTaskDependencies = taskRecurringTaskDependencies.compactMap { dependency -> TaskRecurringTaskDependency? in
            guard dependency.deletedAt == nil else { return nil }
            guard dependency.recurringTaskId == recurringTaskID else { return nil }

            let tombstoneAt = dependency.updatedAt < deletedAt
                ? deletedAt
                : nextUpdatedAt(after: dependency.updatedAt)
            return TaskRecurringTaskDependency(
                taskId: dependency.taskId,
                recurringTaskId: dependency.recurringTaskId,
                requiredCompletions: dependency.requiredCompletions,
                baselineCompletionCount: dependency.baselineCompletionCount,
                createdAt: dependency.createdAt,
                updatedAt: tombstoneAt,
                deletedAt: tombstoneAt,
                serverRevision: dependency.serverRevision
            )
        }

        guard !deletedRecurringTaskDependencies.isEmpty else { return }

        let mergedRecurringTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: taskRecurringTaskDependencies,
            remote: deletedRecurringTaskDependencies
        )

        do {
            try persistReplacedAll(
                taskTaskDependencies: taskTaskDependencies,
                taskRecurringTaskDependencies: mergedRecurringTaskDependencies
            )
        } catch {
            assertionFailure("Failed to delete task dependencies for recurringTask deletion: \(error)")
            return
        }

        guard shouldNotifySync else { return }
        markDirtyAndNotify(kind: .taskRecurringTaskDependencies, ids: deletedRecurringTaskDependencies.map(\.id))
    }

    func updateRecurringTaskDependencyRequiredCompletions(
        taskId: RecordID,
        recurringTaskId: RecordID,
        requiredCompletions: Int,
        tradeStore: TradeStore,
        shouldNotifySync: Bool = true
    ) {
        guard let existing = activeRecurringTaskDependencies(for: taskId).first(where: { $0.recurringTaskId == recurringTaskId }) else {
            return
        }

        let updatedAt = nextUpdatedAt(after: existing.updatedAt)
        let updated = TaskRecurringTaskDependency(
            taskId: existing.taskId,
            recurringTaskId: existing.recurringTaskId,
            requiredCompletions: requiredCompletions,
            baselineCompletionCount: tradeStore.recurringTaskCompletionCount(recurringTaskId: recurringTaskId),
            createdAt: existing.createdAt,
            updatedAt: updatedAt,
            deletedAt: existing.deletedAt,
            serverRevision: existing.serverRevision
        )

        let merged = OwnerScopedRecordSupport.mergeRecords(local: taskRecurringTaskDependencies, remote: [updated])
        do {
            try persistReplacedAll(
                taskTaskDependencies: taskTaskDependencies,
                taskRecurringTaskDependencies: merged
            )
        } catch {
            assertionFailure("Failed to update recurringTask dependency count: \(error)")
            return
        }

        guard shouldNotifySync else { return }
        markDirtyAndNotify(kind: .taskRecurringTaskDependencies, ids: [updated.id])
    }

    func getDirtyTaskTaskDependencies(ids: Set<RecordID>) -> [TaskTaskDependency] {
        taskTaskDependencies.filter { ids.contains($0.id) }
    }

    func getDirtyTaskRecurringTaskDependencies(ids: Set<RecordID>) -> [TaskRecurringTaskDependency] {
        taskRecurringTaskDependencies.filter { ids.contains($0.id) }
    }

    func persistReplacedAll(
        taskTaskDependencies authoritativeTaskTaskDependencies: [TaskTaskDependency],
        taskRecurringTaskDependencies authoritativeTaskRecurringTaskDependencies: [TaskRecurringTaskDependency]
    ) throws {
        let sortedTaskTaskDependencies = OwnerScopedRecordSupport.sorted(authoritativeTaskTaskDependencies)
        let sortedTaskRecurringTaskDependencies = OwnerScopedRecordSupport.sorted(authoritativeTaskRecurringTaskDependencies)

        try database.transaction(at: databaseURL) { db in
            try self.replaceRows(
                ownerID: self.currentOwnerID,
                taskTaskDependencies: sortedTaskTaskDependencies,
                taskRecurringTaskDependencies: sortedTaskRecurringTaskDependencies,
                on: db
            )
        }

        taskTaskDependencies = sortedTaskTaskDependencies
        taskRecurringTaskDependencies = sortedTaskRecurringTaskDependencies
    }

    func persistReplacedAll(
        taskTaskDependencies authoritativeTaskTaskDependencies: [TaskTaskDependency],
        taskRecurringTaskDependencies authoritativeTaskRecurringTaskDependencies: [TaskRecurringTaskDependency],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        let sortedTaskTaskDependencies = OwnerScopedRecordSupport.sorted(authoritativeTaskTaskDependencies)
        let sortedTaskRecurringTaskDependencies = OwnerScopedRecordSupport.sorted(authoritativeTaskRecurringTaskDependencies)
        try replaceRows(
            ownerID: currentOwnerID,
            taskTaskDependencies: sortedTaskTaskDependencies,
            taskRecurringTaskDependencies: sortedTaskRecurringTaskDependencies,
            on: databaseHandle
        )
    }

    func purgeDeleted(
        taskTaskDependencyIDs dirtyTaskTaskDependencyIDs: Set<RecordID>,
        taskRecurringTaskDependencyIDs dirtyTaskRecurringTaskDependencyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try purgeDeletedTaskTaskDependencies(excluding: dirtyTaskTaskDependencyIDs, on: databaseHandle)
        try purgeDeletedTaskRecurringTaskDependencies(excluding: dirtyTaskRecurringTaskDependencyIDs, on: databaseHandle)
    }

    func deleteDependencies(
        taskTaskDependencyIDs: Set<RecordID>,
        taskRecurringTaskDependencyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try deleteDependencyRows(
            tableName: "task_task_dependencies",
            keyColumnA: "task_id",
            keyColumnB: "depends_on_task_id",
            ids: taskTaskDependencyIDs,
            on: databaseHandle
        )
        try deleteDependencyRows(
            tableName: "task_recurring_task_dependencies",
            keyColumnA: "task_id",
            keyColumnB: "recurring_task_id",
            ids: taskRecurringTaskDependencyIDs,
            on: databaseHandle
        )
    }

    private func purgeDeletedTaskTaskDependencies(
        excluding dirtyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        if dirtyIDs.isEmpty {
            try database.execute(
                "DELETE FROM task_task_dependencies WHERE owner_id = ? AND deleted_at IS NOT NULL",
                bindings: [.text(currentOwnerID)],
                on: databaseHandle
            )
            return
        }

        let pairs = dirtyIDs.map { pairColumns(for: $0) }
        let placeholders = Array(repeating: "(?, ?)", count: pairs.count).joined(separator: ", ")
        let bindings: [SQLiteValue] = [.text(currentOwnerID)] + pairs.flatMap { [.text($0.0.rawValue), .text($0.1.rawValue)] }
        try database.execute(
            "DELETE FROM task_task_dependencies WHERE owner_id = ? AND deleted_at IS NOT NULL AND (task_id, depends_on_task_id) NOT IN (\(placeholders))",
            bindings: bindings,
            on: databaseHandle
        )
    }

    private func purgeDeletedTaskRecurringTaskDependencies(
        excluding dirtyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        if dirtyIDs.isEmpty {
            try database.execute(
                "DELETE FROM task_recurring_task_dependencies WHERE owner_id = ? AND deleted_at IS NOT NULL",
                bindings: [.text(currentOwnerID)],
                on: databaseHandle
            )
            return
        }

        let pairs = dirtyIDs.map { pairColumns(for: $0) }
        let placeholders = Array(repeating: "(?, ?)", count: pairs.count).joined(separator: ", ")
        let bindings: [SQLiteValue] = [.text(currentOwnerID)] + pairs.flatMap { [.text($0.0.rawValue), .text($0.1.rawValue)] }
        try database.execute(
            "DELETE FROM task_recurring_task_dependencies WHERE owner_id = ? AND deleted_at IS NOT NULL AND (task_id, recurring_task_id) NOT IN (\(placeholders))",
            bindings: bindings,
            on: databaseHandle
        )
    }

    private func replaceRows(
        ownerID: String,
        taskTaskDependencies: [TaskTaskDependency],
        taskRecurringTaskDependencies: [TaskRecurringTaskDependency],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try database.execute(
            "DELETE FROM task_task_dependencies WHERE owner_id = ?",
            bindings: [.text(ownerID)],
            on: databaseHandle
        )
        try database.execute(
            "DELETE FROM task_recurring_task_dependencies WHERE owner_id = ?",
            bindings: [.text(ownerID)],
            on: databaseHandle
        )

        for dependency in taskTaskDependencies {
            try database.execute(
                """
                INSERT INTO task_task_dependencies (
                    owner_id, task_id, depends_on_task_id, created_at, updated_at, deleted_at, server_revision
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: taskTaskDependencyBindings(dependency, ownerID: ownerID),
                on: databaseHandle
            )
        }

        for dependency in taskRecurringTaskDependencies {
            try database.execute(
                """
                INSERT INTO task_recurring_task_dependencies (
                    owner_id, task_id, recurring_task_id, required_completions, baseline_completion_count, created_at, updated_at, deleted_at, server_revision
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: taskRecurringTaskDependencyBindings(dependency, ownerID: ownerID),
                on: databaseHandle
            )
        }
    }

    private func loadTaskTaskDependencies(ownerID: String) -> [TaskTaskDependency] {
        let fetched = (try? database.query(
            """
            SELECT task_id, depends_on_task_id, created_at, updated_at, deleted_at, server_revision
            FROM task_task_dependencies
            WHERE owner_id = ?
            ORDER BY created_at ASC, task_id ASC, depends_on_task_id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            TaskTaskDependency(
                taskId: RecordID(SQLiteColumn.text(row, index: 0)),
                dependsOnTaskId: RecordID(SQLiteColumn.text(row, index: 1)),
                createdAt: SQLiteColumn.date(row, index: 2),
                updatedAt: SQLiteColumn.date(row, index: 3),
                deletedAt: SQLiteColumn.optionalDate(row, index: 4),
                serverRevision: SQLiteColumn.optionalInt64(row, index: 5)
            )
        }) ?? []

        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func loadTaskRecurringTaskDependencies(ownerID: String) -> [TaskRecurringTaskDependency] {
        let fetched = (try? database.query(
            """
            SELECT task_id, recurring_task_id, required_completions, baseline_completion_count, created_at, updated_at, deleted_at, server_revision
            FROM task_recurring_task_dependencies
            WHERE owner_id = ?
            ORDER BY created_at ASC, task_id ASC, recurring_task_id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            TaskRecurringTaskDependency(
                taskId: RecordID(SQLiteColumn.text(row, index: 0)),
                recurringTaskId: RecordID(SQLiteColumn.text(row, index: 1)),
                requiredCompletions: SQLiteColumn.int(row, index: 2),
                baselineCompletionCount: SQLiteColumn.int(row, index: 3),
                createdAt: SQLiteColumn.date(row, index: 4),
                updatedAt: SQLiteColumn.date(row, index: 5),
                deletedAt: SQLiteColumn.optionalDate(row, index: 6),
                serverRevision: SQLiteColumn.optionalInt64(row, index: 7)
            )
        }) ?? []

        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func refreshAll() {
        taskTaskDependencies = loadTaskTaskDependencies(ownerID: currentOwnerID)
        taskRecurringTaskDependencies = loadTaskRecurringTaskDependencies(ownerID: currentOwnerID)
    }

    private func taskTaskDependencyBindings(_ dependency: TaskTaskDependency, ownerID: String) -> [SQLiteValue] {
        [
            .text(ownerID),
            .text(dependency.taskId.rawValue),
            .text(dependency.dependsOnTaskId.rawValue),
            .double(dependency.createdAt.timeIntervalSince1970),
            .double(dependency.updatedAt.timeIntervalSince1970),
            dependency.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            dependency.serverRevision.map { .int($0) } ?? .null
        ]
    }

    private func taskRecurringTaskDependencyBindings(_ dependency: TaskRecurringTaskDependency, ownerID: String) -> [SQLiteValue] {
        [
            .text(ownerID),
            .text(dependency.taskId.rawValue),
            .text(dependency.recurringTaskId.rawValue),
            .int(Int64(dependency.requiredCompletions)),
            .int(Int64(dependency.baselineCompletionCount)),
            .double(dependency.createdAt.timeIntervalSince1970),
            .double(dependency.updatedAt.timeIntervalSince1970),
            dependency.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            dependency.serverRevision.map { .int($0) } ?? .null
        ]
    }

    private func pairColumns(for id: RecordID) -> (RecordID, RecordID) {
        let parts = id.rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return (id, id) }
        return (RecordID(parts[0]), RecordID(parts[1]))
    }

    private func deleteDependencyRows(
        tableName: String,
        keyColumnA: String,
        keyColumnB: String,
        ids: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        for id in ids {
            let pair = pairColumns(for: id)
            try database.execute(
                "DELETE FROM \(tableName) WHERE owner_id = ? AND \(keyColumnA) = ? AND \(keyColumnB) = ?",
                bindings: [.text(currentOwnerID), .text(pair.0.rawValue), .text(pair.1.rawValue)],
                on: databaseHandle
            )
        }
    }

    private func normalizedTaskTaskDependency(
        _ dependency: TaskTaskDependency,
        existing: TaskTaskDependency?
    ) -> TaskTaskDependency {
        guard let existing else { return dependency }
        let updatedAt = dependency.updatedAt <= existing.updatedAt
            ? nextUpdatedAt(after: existing.updatedAt)
            : dependency.updatedAt

        return TaskTaskDependency(
            taskId: dependency.taskId,
            dependsOnTaskId: dependency.dependsOnTaskId,
            createdAt: dependency.createdAt,
            updatedAt: updatedAt,
            deletedAt: dependency.deletedAt,
            serverRevision: dependency.serverRevision ?? existing.serverRevision
        )
    }

    private func normalizedTaskRecurringTaskDependency(
        _ dependency: TaskRecurringTaskDependency,
        existing: TaskRecurringTaskDependency?
    ) -> TaskRecurringTaskDependency {
        guard let existing else { return dependency }
        let updatedAt = dependency.updatedAt <= existing.updatedAt
            ? nextUpdatedAt(after: existing.updatedAt)
            : dependency.updatedAt

        return TaskRecurringTaskDependency(
            taskId: dependency.taskId,
            recurringTaskId: dependency.recurringTaskId,
            requiredCompletions: dependency.requiredCompletions,
            baselineCompletionCount: dependency.baselineCompletionCount,
            createdAt: dependency.createdAt,
            updatedAt: updatedAt,
            deletedAt: dependency.deletedAt,
            serverRevision: dependency.serverRevision ?? existing.serverRevision
        )
    }

    private func nextUpdatedAt(after existingUpdatedAt: Date) -> Date {
        let now = Date()
        return now > existingUpdatedAt ? now : existingUpdatedAt.addingTimeInterval(0.001)
    }

    private func markDirtyAndNotify(kind: SyncEntityKind, ids: [RecordID]) {
        guard !ids.isEmpty else { return }

        if currentOwnerID != StorageOwner.local {
            syncStateStore.markDirty(userID: currentOwnerID, kind: kind, ids: ids)
        }
        notifySync(kind: kind, ids: ids)
    }

    private func notifySync(kind: SyncEntityKind, ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: kind, recordIDs: ids))
    }
}
