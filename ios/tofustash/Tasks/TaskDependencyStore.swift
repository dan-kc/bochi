import Foundation

@Observable
@MainActor
final class TaskDependencyStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore

    private(set) var currentOwnerID: String
    private(set) var taskTaskDependencies: [TaskTaskDependency] = []
    private(set) var taskHabitDependencies: [TaskHabitDependency] = []

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
    ) -> (taskTaskDependencyIDs: [RecordID], taskHabitDependencyIDs: [RecordID]) {
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
    ) throws -> (taskTaskDependencyIDs: [RecordID], taskHabitDependencyIDs: [RecordID]) {
        guard sourceOwnerID != destinationOwnerID else { return ([], []) }

        let sourceTaskTaskDependencies = loadTaskTaskDependencies(ownerID: sourceOwnerID)
        let sourceTaskHabitDependencies = loadTaskHabitDependencies(ownerID: sourceOwnerID)
        let destinationTaskTaskDependencies = loadTaskTaskDependencies(ownerID: destinationOwnerID)
        let destinationTaskHabitDependencies = loadTaskHabitDependencies(ownerID: destinationOwnerID)

        let mergedTaskTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: destinationTaskTaskDependencies,
            remote: sourceTaskTaskDependencies
        )
        let mergedTaskHabitDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: destinationTaskHabitDependencies,
            remote: sourceTaskHabitDependencies
        )

        try replaceRows(
            ownerID: sourceOwnerID,
            taskTaskDependencies: [],
            taskHabitDependencies: [],
            on: databaseHandle
        )
        try replaceRows(
            ownerID: destinationOwnerID,
            taskTaskDependencies: mergedTaskTaskDependencies,
            taskHabitDependencies: mergedTaskHabitDependencies,
            on: databaseHandle
        )

        return (
            taskTaskDependencyIDs: sourceTaskTaskDependencies.map(\.id),
            taskHabitDependencyIDs: sourceTaskHabitDependencies.map(\.id)
        )
    }

    func activeTaskDependencies(for taskID: RecordID) -> [TaskTaskDependency] {
        taskTaskDependencies.filter { $0.taskId == taskID && $0.deletedAt == nil }
    }

    func activeHabitDependencies(for taskID: RecordID) -> [TaskHabitDependency] {
        taskHabitDependencies.filter { $0.taskId == taskID && $0.deletedAt == nil }
    }

    func isTaskBlocked(
        _ task: TaskItem,
        taskStore: TaskStore,
        tradeStore: TradeStore
    ) -> Bool {
        guard task.deletedAt == nil, task.completedAt == nil else { return false }

        if activeTaskDependencies(for: task.id).contains(where: { dependency in
            guard let prerequisiteTask = taskStore.tasks.first(where: { $0.id == dependency.dependsOnTaskId }) else {
                return false
            }
            guard prerequisiteTask.deletedAt == nil else { return false }
            return prerequisiteTask.completedAt == nil
        }) {
            return true
        }

        return activeHabitDependencies(for: task.id).contains { dependency in
            habitDependencyProgress(for: dependency, tradeStore: tradeStore) < dependency.requiredCompletions
        }
    }

    func habitDependencyProgress(
        for dependency: TaskHabitDependency,
        tradeStore: TradeStore
    ) -> Int {
        max(0, tradeStore.habitCompletionCount(habitId: dependency.habitId) - dependency.baselineCompletionCount)
    }

    func replaceDependencies(
        for taskID: RecordID,
        taskDependencies: [TaskTaskDependency],
        habitDependencies: [TaskHabitDependency],
        shouldNotifySync: Bool = true
    ) {
        let existingTaskDependenciesByID = Dictionary(uniqueKeysWithValues: taskTaskDependencies.map { ($0.id, $0) })
        let existingHabitDependenciesByID = Dictionary(uniqueKeysWithValues: taskHabitDependencies.map { ($0.id, $0) })
        let normalizedTaskDependencies = taskDependencies.map { dependency in
            normalizedTaskTaskDependency(dependency, existing: existingTaskDependenciesByID[dependency.id])
        }
        let normalizedHabitDependencies = habitDependencies.map { dependency in
            normalizedTaskHabitDependency(dependency, existing: existingHabitDependenciesByID[dependency.id])
        }

        let existingTaskDependencies = activeTaskDependencies(for: taskID)
        let existingHabitDependencies = activeHabitDependencies(for: taskID)
        let incomingTaskDependencyIDs = Set(normalizedTaskDependencies.map(\.id))
        let incomingHabitDependencyIDs = Set(normalizedHabitDependencies.map(\.id))

        let deletedTaskDependencies = existingTaskDependencies
            .filter { !incomingTaskDependencyIDs.contains($0.id) }
            .map {
                let updatedAt = nextUpdatedAt(after: $0.updatedAt)
                return TaskTaskDependency(
                    taskId: $0.taskId,
                    dependsOnTaskId: $0.dependsOnTaskId,
                    createdAt: $0.createdAt,
                    updatedAt: updatedAt,
                    deletedAt: updatedAt
                )
            }

        let deletedHabitDependencies = existingHabitDependencies
            .filter { !incomingHabitDependencyIDs.contains($0.id) }
            .map {
                let updatedAt = nextUpdatedAt(after: $0.updatedAt)
                return TaskHabitDependency(
                    taskId: $0.taskId,
                    habitId: $0.habitId,
                    requiredCompletions: $0.requiredCompletions,
                    baselineCompletionCount: $0.baselineCompletionCount,
                    createdAt: $0.createdAt,
                    updatedAt: updatedAt,
                    deletedAt: updatedAt
                )
            }

        let mergedTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: taskTaskDependencies,
            remote: normalizedTaskDependencies + deletedTaskDependencies
        )
        let mergedHabitDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: taskHabitDependencies,
            remote: normalizedHabitDependencies + deletedHabitDependencies
        )

        do {
            try persistReplacedAll(
                taskTaskDependencies: mergedTaskDependencies,
                taskHabitDependencies: mergedHabitDependencies
            )
        } catch {
            assertionFailure("Failed to replace task dependencies: \(error)")
            return
        }

        guard shouldNotifySync else { return }

        let dirtyTaskTaskIDs = normalizedTaskDependencies.map(\.id) + deletedTaskDependencies.map(\.id)
        let dirtyTaskHabitIDs = normalizedHabitDependencies.map(\.id) + deletedHabitDependencies.map(\.id)

        if !dirtyTaskTaskIDs.isEmpty {
            if currentOwnerID != StorageOwner.local {
                syncStateStore.markDirty(
                    userID: currentOwnerID,
                    kind: .taskTaskDependencies,
                    ids: dirtyTaskTaskIDs
                )
            }
            notifySync(kind: .taskTaskDependencies, ids: dirtyTaskTaskIDs)
        }
        if !dirtyTaskHabitIDs.isEmpty {
            if currentOwnerID != StorageOwner.local {
                syncStateStore.markDirty(
                    userID: currentOwnerID,
                    kind: .taskHabitDependencies,
                    ids: dirtyTaskHabitIDs
                )
            }
            notifySync(kind: .taskHabitDependencies, ids: dirtyTaskHabitIDs)
        }
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
                deletedAt: tombstoneAt
            )
        }

        let deletedHabitDependencies = taskHabitDependencies.compactMap { dependency -> TaskHabitDependency? in
            guard dependency.deletedAt == nil else { return nil }
            guard dependency.taskId == taskID else { return nil }

            let tombstoneAt = dependency.updatedAt < deletedAt
                ? deletedAt
                : nextUpdatedAt(after: dependency.updatedAt)
            return TaskHabitDependency(
                taskId: dependency.taskId,
                habitId: dependency.habitId,
                requiredCompletions: dependency.requiredCompletions,
                baselineCompletionCount: dependency.baselineCompletionCount,
                createdAt: dependency.createdAt,
                updatedAt: tombstoneAt,
                deletedAt: tombstoneAt
            )
        }

        guard !deletedTaskDependencies.isEmpty || !deletedHabitDependencies.isEmpty else { return }

        let mergedTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: taskTaskDependencies,
            remote: deletedTaskDependencies
        )
        let mergedHabitDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: taskHabitDependencies,
            remote: deletedHabitDependencies
        )

        do {
            try persistReplacedAll(
                taskTaskDependencies: mergedTaskDependencies,
                taskHabitDependencies: mergedHabitDependencies
            )
        } catch {
            assertionFailure("Failed to delete task dependencies for task deletion: \(error)")
            return
        }

        guard shouldNotifySync else { return }

        let dirtyTaskTaskIDs = deletedTaskDependencies.map(\.id)
        let dirtyTaskHabitIDs = deletedHabitDependencies.map(\.id)

        if !dirtyTaskTaskIDs.isEmpty {
            if currentOwnerID != StorageOwner.local {
                syncStateStore.markDirty(
                    userID: currentOwnerID,
                    kind: .taskTaskDependencies,
                    ids: dirtyTaskTaskIDs
                )
            }
            notifySync(kind: .taskTaskDependencies, ids: dirtyTaskTaskIDs)
        }

        if !dirtyTaskHabitIDs.isEmpty {
            if currentOwnerID != StorageOwner.local {
                syncStateStore.markDirty(
                    userID: currentOwnerID,
                    kind: .taskHabitDependencies,
                    ids: dirtyTaskHabitIDs
                )
            }
            notifySync(kind: .taskHabitDependencies, ids: dirtyTaskHabitIDs)
        }
    }

    func updateHabitDependencyRequiredCompletions(
        taskId: RecordID,
        habitId: RecordID,
        requiredCompletions: Int,
        tradeStore: TradeStore,
        shouldNotifySync: Bool = true
    ) {
        guard let existing = activeHabitDependencies(for: taskId).first(where: { $0.habitId == habitId }) else {
            return
        }

        let updatedAt = nextUpdatedAt(after: existing.updatedAt)
        let updated = TaskHabitDependency(
            taskId: existing.taskId,
            habitId: existing.habitId,
            requiredCompletions: requiredCompletions,
            baselineCompletionCount: tradeStore.habitCompletionCount(habitId: habitId),
            createdAt: existing.createdAt,
            updatedAt: updatedAt,
            deletedAt: existing.deletedAt
        )

        let merged = OwnerScopedRecordSupport.mergeRecords(local: taskHabitDependencies, remote: [updated])
        do {
            try persistReplacedAll(
                taskTaskDependencies: taskTaskDependencies,
                taskHabitDependencies: merged
            )
        } catch {
            assertionFailure("Failed to update habit dependency count: \(error)")
            return
        }

        if shouldNotifySync {
            if currentOwnerID != StorageOwner.local {
                syncStateStore.markDirty(
                    userID: currentOwnerID,
                    kind: .taskHabitDependencies,
                    ids: [updated.id]
                )
            }
            notifySync(kind: .taskHabitDependencies, ids: [updated.id])
        }
    }

    func getDirtyTaskTaskDependencies(ids: Set<RecordID>) -> [TaskTaskDependency] {
        taskTaskDependencies.filter { ids.contains($0.id) }
    }

    func getDirtyTaskHabitDependencies(ids: Set<RecordID>) -> [TaskHabitDependency] {
        taskHabitDependencies.filter { ids.contains($0.id) }
    }

    func persistReplacedAll(
        taskTaskDependencies authoritativeTaskTaskDependencies: [TaskTaskDependency],
        taskHabitDependencies authoritativeTaskHabitDependencies: [TaskHabitDependency]
    ) throws {
        let sortedTaskTaskDependencies = OwnerScopedRecordSupport.sorted(authoritativeTaskTaskDependencies)
        let sortedTaskHabitDependencies = OwnerScopedRecordSupport.sorted(authoritativeTaskHabitDependencies)

        try database.transaction(at: databaseURL) { db in
            try self.replaceRows(
                ownerID: self.currentOwnerID,
                taskTaskDependencies: sortedTaskTaskDependencies,
                taskHabitDependencies: sortedTaskHabitDependencies,
                on: db
            )
        }

        taskTaskDependencies = sortedTaskTaskDependencies
        taskHabitDependencies = sortedTaskHabitDependencies
    }

    func persistReplacedAll(
        taskTaskDependencies authoritativeTaskTaskDependencies: [TaskTaskDependency],
        taskHabitDependencies authoritativeTaskHabitDependencies: [TaskHabitDependency],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        let sortedTaskTaskDependencies = OwnerScopedRecordSupport.sorted(authoritativeTaskTaskDependencies)
        let sortedTaskHabitDependencies = OwnerScopedRecordSupport.sorted(authoritativeTaskHabitDependencies)
        try replaceRows(
            ownerID: currentOwnerID,
            taskTaskDependencies: sortedTaskTaskDependencies,
            taskHabitDependencies: sortedTaskHabitDependencies,
            on: databaseHandle
        )
    }

    func purgeDeleted(
        taskTaskDependencyIDs dirtyTaskTaskDependencyIDs: Set<RecordID>,
        taskHabitDependencyIDs dirtyTaskHabitDependencyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try purgeDeletedTaskTaskDependencies(excluding: dirtyTaskTaskDependencyIDs, on: databaseHandle)
        try purgeDeletedTaskHabitDependencies(excluding: dirtyTaskHabitDependencyIDs, on: databaseHandle)
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

    private func purgeDeletedTaskHabitDependencies(
        excluding dirtyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        if dirtyIDs.isEmpty {
            try database.execute(
                "DELETE FROM task_habit_dependencies WHERE owner_id = ? AND deleted_at IS NOT NULL",
                bindings: [.text(currentOwnerID)],
                on: databaseHandle
            )
            return
        }

        let pairs = dirtyIDs.map { pairColumns(for: $0) }
        let placeholders = Array(repeating: "(?, ?)", count: pairs.count).joined(separator: ", ")
        let bindings: [SQLiteValue] = [.text(currentOwnerID)] + pairs.flatMap { [.text($0.0.rawValue), .text($0.1.rawValue)] }
        try database.execute(
            "DELETE FROM task_habit_dependencies WHERE owner_id = ? AND deleted_at IS NOT NULL AND (task_id, habit_id) NOT IN (\(placeholders))",
            bindings: bindings,
            on: databaseHandle
        )
    }

    private func replaceRows(
        ownerID: String,
        taskTaskDependencies: [TaskTaskDependency],
        taskHabitDependencies: [TaskHabitDependency],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try database.execute(
            "DELETE FROM task_task_dependencies WHERE owner_id = ?",
            bindings: [.text(ownerID)],
            on: databaseHandle
        )
        try database.execute(
            "DELETE FROM task_habit_dependencies WHERE owner_id = ?",
            bindings: [.text(ownerID)],
            on: databaseHandle
        )

        for dependency in taskTaskDependencies {
            try database.execute(
                """
                INSERT INTO task_task_dependencies (
                    owner_id, task_id, depends_on_task_id, created_at, updated_at, deleted_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                bindings: taskTaskDependencyBindings(dependency, ownerID: ownerID),
                on: databaseHandle
            )
        }

        for dependency in taskHabitDependencies {
            try database.execute(
                """
                INSERT INTO task_habit_dependencies (
                    owner_id, task_id, habit_id, required_completions, baseline_completion_count, created_at, updated_at, deleted_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: taskHabitDependencyBindings(dependency, ownerID: ownerID),
                on: databaseHandle
            )
        }
    }

    private func loadTaskTaskDependencies(ownerID: String) -> [TaskTaskDependency] {
        let fetched = (try? database.query(
            """
            SELECT task_id, depends_on_task_id, created_at, updated_at, deleted_at
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
                deletedAt: SQLiteColumn.optionalDate(row, index: 4)
            )
        }) ?? []

        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func loadTaskHabitDependencies(ownerID: String) -> [TaskHabitDependency] {
        let fetched = (try? database.query(
            """
            SELECT task_id, habit_id, required_completions, baseline_completion_count, created_at, updated_at, deleted_at
            FROM task_habit_dependencies
            WHERE owner_id = ?
            ORDER BY created_at ASC, task_id ASC, habit_id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            TaskHabitDependency(
                taskId: RecordID(SQLiteColumn.text(row, index: 0)),
                habitId: RecordID(SQLiteColumn.text(row, index: 1)),
                requiredCompletions: SQLiteColumn.int(row, index: 2),
                baselineCompletionCount: SQLiteColumn.int(row, index: 3),
                createdAt: SQLiteColumn.date(row, index: 4),
                updatedAt: SQLiteColumn.date(row, index: 5),
                deletedAt: SQLiteColumn.optionalDate(row, index: 6)
            )
        }) ?? []

        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func refreshAll() {
        taskTaskDependencies = loadTaskTaskDependencies(ownerID: currentOwnerID)
        taskHabitDependencies = loadTaskHabitDependencies(ownerID: currentOwnerID)
    }

    private func taskTaskDependencyBindings(_ dependency: TaskTaskDependency, ownerID: String) -> [SQLiteValue] {
        [
            .text(ownerID),
            .text(dependency.taskId.rawValue),
            .text(dependency.dependsOnTaskId.rawValue),
            .double(dependency.createdAt.timeIntervalSince1970),
            .double(dependency.updatedAt.timeIntervalSince1970),
            dependency.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null
        ]
    }

    private func taskHabitDependencyBindings(_ dependency: TaskHabitDependency, ownerID: String) -> [SQLiteValue] {
        [
            .text(ownerID),
            .text(dependency.taskId.rawValue),
            .text(dependency.habitId.rawValue),
            .int(Int64(dependency.requiredCompletions)),
            .int(Int64(dependency.baselineCompletionCount)),
            .double(dependency.createdAt.timeIntervalSince1970),
            .double(dependency.updatedAt.timeIntervalSince1970),
            dependency.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null
        ]
    }

    private func pairColumns(for id: RecordID) -> (RecordID, RecordID) {
        let parts = id.rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return (id, id) }
        return (RecordID(parts[0]), RecordID(parts[1]))
    }

    private func normalizedTaskTaskDependency(
        _ dependency: TaskTaskDependency,
        existing: TaskTaskDependency?
    ) -> TaskTaskDependency {
        guard let existing else { return dependency }
        guard dependency.updatedAt <= existing.updatedAt else { return dependency }

        return TaskTaskDependency(
            taskId: dependency.taskId,
            dependsOnTaskId: dependency.dependsOnTaskId,
            createdAt: dependency.createdAt,
            updatedAt: nextUpdatedAt(after: existing.updatedAt),
            deletedAt: dependency.deletedAt
        )
    }

    private func normalizedTaskHabitDependency(
        _ dependency: TaskHabitDependency,
        existing: TaskHabitDependency?
    ) -> TaskHabitDependency {
        guard let existing else { return dependency }
        guard dependency.updatedAt <= existing.updatedAt else { return dependency }

        return TaskHabitDependency(
            taskId: dependency.taskId,
            habitId: dependency.habitId,
            requiredCompletions: dependency.requiredCompletions,
            baselineCompletionCount: dependency.baselineCompletionCount,
            createdAt: dependency.createdAt,
            updatedAt: nextUpdatedAt(after: existing.updatedAt),
            deletedAt: dependency.deletedAt
        )
    }

    private func nextUpdatedAt(after existingUpdatedAt: Date) -> Date {
        let now = Date()
        return now > existingUpdatedAt ? now : existingUpdatedAt.addingTimeInterval(0.001)
    }

    private func notifySync(kind: SyncEntityKind, ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: kind, recordIDs: ids))
    }
}
