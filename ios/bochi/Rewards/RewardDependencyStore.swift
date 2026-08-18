import Foundation

// Sync flow: reward dependency edits mark graph link rows dirty and publish
// mutations; sync replacement methods refresh links without re-triggering sync.
@Observable
@MainActor
final class RewardDependencyStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore

    private(set) var currentOwnerID: String
    private(set) var rewardTaskDependencies: [RewardTaskDependency] = []
    private(set) var rewardRecurringTaskDependencies: [RewardRecurringTaskDependency] = []

    init(storageURL: URL? = nil, initialOwnerID: String = "local-device") {
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
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> (rewardTaskDependencyIDs: [RecordID], rewardRecurringTaskDependencyIDs: [RecordID]) {
        guard sourceOwnerID != destinationOwnerID else { return ([], []) }

        let sourceTaskDependencies = loadRewardTaskDependencies(ownerID: sourceOwnerID)
        let sourceRecurringTaskDependencies = loadRewardRecurringTaskDependencies(ownerID: sourceOwnerID)
        let destinationTaskDependencies = loadRewardTaskDependencies(ownerID: destinationOwnerID)
        let destinationRecurringTaskDependencies = loadRewardRecurringTaskDependencies(ownerID: destinationOwnerID)

        try replaceRows(
            ownerID: sourceOwnerID,
            rewardTaskDependencies: [],
            rewardRecurringTaskDependencies: [],
            on: databaseHandle
        )
        try replaceRows(
            ownerID: destinationOwnerID,
            rewardTaskDependencies: OwnerScopedRecordSupport.mergeRecords(local: destinationTaskDependencies, remote: sourceTaskDependencies),
            rewardRecurringTaskDependencies: OwnerScopedRecordSupport.mergeRecords(local: destinationRecurringTaskDependencies, remote: sourceRecurringTaskDependencies),
            on: databaseHandle
        )

        return (
            rewardTaskDependencyIDs: sourceTaskDependencies.map(\.id),
            rewardRecurringTaskDependencyIDs: sourceRecurringTaskDependencies.map(\.id)
        )
    }

    func activeTaskDependencies(for rewardID: RecordID) -> [RewardTaskDependency] {
        rewardTaskDependencies.filter { $0.rewardId == rewardID && $0.deletedAt == nil }
    }

    func activeRecurringTaskDependencies(for rewardID: RecordID) -> [RewardRecurringTaskDependency] {
        rewardRecurringTaskDependencies.filter { $0.rewardId == rewardID && $0.deletedAt == nil }
    }

    func hasDependencies(for rewardID: RecordID) -> Bool {
        !activeTaskDependencies(for: rewardID).isEmpty || !activeRecurringTaskDependencies(for: rewardID).isEmpty
    }

    func isRewardBlocked(
        _ reward: Reward,
        taskStore: TaskStore,
        tradeStore: TradeStore,
        hasPremiumAccess: Bool = true
    ) -> Bool {
        guard hasPremiumAccess else { return false }
        guard reward.deletedAt == nil else { return false }

        if activeTaskDependencies(for: reward.id).contains(where: { dependency in
            guard let prerequisiteTask = taskStore.tasks.first(where: { $0.id == dependency.dependsOnTaskId }) else {
                return false
            }
            guard prerequisiteTask.deletedAt == nil else { return false }
            return tradeStore.latestTaskTrade(taskId: prerequisiteTask.id, includeRefunded: false) == nil
        }) {
            return true
        }

        return activeRecurringTaskDependencies(for: reward.id).contains { dependency in
            recurringTaskDependencyProgress(for: dependency, tradeStore: tradeStore) < dependency.requiredCompletions
        }
    }

    func recurringTaskDependencyProgress(for dependency: RewardRecurringTaskDependency, tradeStore: TradeStore) -> Int {
        max(0, tradeStore.recurringTaskCompletionCount(recurringTaskId: dependency.recurringTaskId) - dependency.baselineCompletionCount)
    }

    func replaceDependencies(
        for rewardID: RecordID,
        taskDependencies: [RewardTaskDependency],
        recurringTaskDependencies: [RewardRecurringTaskDependency],
        shouldNotifySync: Bool = true
    ) {
        let existingTaskDependenciesByID = Dictionary(uniqueKeysWithValues: rewardTaskDependencies.map { ($0.id, $0) })
        let existingRecurringTaskDependenciesByID = Dictionary(uniqueKeysWithValues: rewardRecurringTaskDependencies.map { ($0.id, $0) })
        let normalizedTaskDependencies = taskDependencies.map { dependency in
            normalizedRewardTaskDependency(dependency, existing: existingTaskDependenciesByID[dependency.id])
        }
        let normalizedRecurringTaskDependencies = recurringTaskDependencies.map { dependency in
            normalizedRewardRecurringTaskDependency(dependency, existing: existingRecurringTaskDependenciesByID[dependency.id])
        }

        let incomingTaskIDs = Set(normalizedTaskDependencies.map(\.id))
        let incomingRecurringTaskIDs = Set(normalizedRecurringTaskDependencies.map(\.id))
        let deletedTaskDependencies = activeTaskDependencies(for: rewardID)
            .filter { !incomingTaskIDs.contains($0.id) }
            .map { dependency in
                let updatedAt = nextUpdatedAt(after: dependency.updatedAt)
                return RewardTaskDependency(
                    rewardId: dependency.rewardId,
                    dependsOnTaskId: dependency.dependsOnTaskId,
                    createdAt: dependency.createdAt,
                    updatedAt: updatedAt,
                    deletedAt: updatedAt,
                    serverRevision: dependency.serverRevision
                )
            }
        let deletedRecurringTaskDependencies = activeRecurringTaskDependencies(for: rewardID)
            .filter { !incomingRecurringTaskIDs.contains($0.id) }
            .map { dependency in
                let updatedAt = nextUpdatedAt(after: dependency.updatedAt)
                return RewardRecurringTaskDependency(
                    rewardId: dependency.rewardId,
                    recurringTaskId: dependency.recurringTaskId,
                    requiredCompletions: dependency.requiredCompletions,
                    baselineCompletionCount: dependency.baselineCompletionCount,
                    createdAt: dependency.createdAt,
                    updatedAt: updatedAt,
                    deletedAt: updatedAt,
                    serverRevision: dependency.serverRevision
                )
            }

        let mergedTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: rewardTaskDependencies,
            remote: normalizedTaskDependencies + deletedTaskDependencies
        )
        let mergedRecurringTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: rewardRecurringTaskDependencies,
            remote: normalizedRecurringTaskDependencies + deletedRecurringTaskDependencies
        )

        do {
            try persistReplacedAll(
                rewardTaskDependencies: mergedTaskDependencies,
                rewardRecurringTaskDependencies: mergedRecurringTaskDependencies
            )
        } catch {
            assertionFailure("Failed to replace reward dependencies: \(error)")
            return
        }

        guard shouldNotifySync else { return }
        markDirtyAndNotify(kind: .rewardTaskDependencies, ids: normalizedTaskDependencies.map(\.id) + deletedTaskDependencies.map(\.id))
        markDirtyAndNotify(kind: .rewardRecurringTaskDependencies, ids: normalizedRecurringTaskDependencies.map(\.id) + deletedRecurringTaskDependencies.map(\.id))
    }

    func resetRecurringTaskDependencies(for rewardID: RecordID, tradeStore: TradeStore, shouldNotifySync: Bool = true) {
        let updatedDependencies = activeRecurringTaskDependencies(for: rewardID).map { dependency in
            let updatedAt = nextUpdatedAt(after: dependency.updatedAt)
            return RewardRecurringTaskDependency(
                rewardId: dependency.rewardId,
                recurringTaskId: dependency.recurringTaskId,
                requiredCompletions: dependency.requiredCompletions,
                baselineCompletionCount: tradeStore.recurringTaskCompletionCount(recurringTaskId: dependency.recurringTaskId),
                createdAt: dependency.createdAt,
                updatedAt: updatedAt,
                deletedAt: dependency.deletedAt,
                serverRevision: dependency.serverRevision
            )
        }
        guard !updatedDependencies.isEmpty else { return }

        let merged = OwnerScopedRecordSupport.mergeRecords(local: rewardRecurringTaskDependencies, remote: updatedDependencies)
        do {
            try persistReplacedAll(
                rewardTaskDependencies: rewardTaskDependencies,
                rewardRecurringTaskDependencies: merged
            )
        } catch {
            assertionFailure("Failed to reset reward recurringTask dependencies: \(error)")
            return
        }

        guard shouldNotifySync else { return }
        markDirtyAndNotify(kind: .rewardRecurringTaskDependencies, ids: updatedDependencies.map(\.id))
    }

    func deleteDependenciesReferencingTask(
        _ taskID: RecordID,
        deletedAt: Date = Date(),
        shouldNotifySync: Bool = true
    ) {
        let deletedTaskDependencies = rewardTaskDependencies.compactMap { dependency -> RewardTaskDependency? in
            guard dependency.deletedAt == nil else { return nil }
            guard dependency.dependsOnTaskId == taskID else { return nil }

            let tombstoneAt = dependency.updatedAt < deletedAt
                ? deletedAt
                : nextUpdatedAt(after: dependency.updatedAt)
            return RewardTaskDependency(
                rewardId: dependency.rewardId,
                dependsOnTaskId: dependency.dependsOnTaskId,
                createdAt: dependency.createdAt,
                updatedAt: tombstoneAt,
                deletedAt: tombstoneAt,
                serverRevision: dependency.serverRevision
            )
        }

        mergeDeletedDependencies(
            taskDependencies: deletedTaskDependencies,
            recurringTaskDependencies: [],
            shouldNotifySync: shouldNotifySync
        )
    }

    func deleteDependenciesReferencingReward(
        _ rewardID: RecordID,
        deletedAt: Date = Date(),
        shouldNotifySync: Bool = true
    ) {
        let deletedTaskDependencies = activeTaskDependencies(for: rewardID).map { dependency in
            let tombstoneAt = dependency.updatedAt < deletedAt
                ? deletedAt
                : nextUpdatedAt(after: dependency.updatedAt)
            return RewardTaskDependency(
                rewardId: dependency.rewardId,
                dependsOnTaskId: dependency.dependsOnTaskId,
                createdAt: dependency.createdAt,
                updatedAt: tombstoneAt,
                deletedAt: tombstoneAt,
                serverRevision: dependency.serverRevision
            )
        }

        let deletedRecurringTaskDependencies = activeRecurringTaskDependencies(for: rewardID).map { dependency in
            let tombstoneAt = dependency.updatedAt < deletedAt
                ? deletedAt
                : nextUpdatedAt(after: dependency.updatedAt)
            return RewardRecurringTaskDependency(
                rewardId: dependency.rewardId,
                recurringTaskId: dependency.recurringTaskId,
                requiredCompletions: dependency.requiredCompletions,
                baselineCompletionCount: dependency.baselineCompletionCount,
                createdAt: dependency.createdAt,
                updatedAt: tombstoneAt,
                deletedAt: tombstoneAt,
                serverRevision: dependency.serverRevision
            )
        }

        mergeDeletedDependencies(
            taskDependencies: deletedTaskDependencies,
            recurringTaskDependencies: deletedRecurringTaskDependencies,
            shouldNotifySync: shouldNotifySync
        )
    }

    func deleteDependenciesReferencingRecurringTask(
        _ recurringTaskID: RecordID,
        deletedAt: Date = Date(),
        shouldNotifySync: Bool = true
    ) {
        let deletedRecurringTaskDependencies = rewardRecurringTaskDependencies.compactMap { dependency -> RewardRecurringTaskDependency? in
            guard dependency.deletedAt == nil else { return nil }
            guard dependency.recurringTaskId == recurringTaskID else { return nil }

            let tombstoneAt = dependency.updatedAt < deletedAt
                ? deletedAt
                : nextUpdatedAt(after: dependency.updatedAt)
            return RewardRecurringTaskDependency(
                rewardId: dependency.rewardId,
                recurringTaskId: dependency.recurringTaskId,
                requiredCompletions: dependency.requiredCompletions,
                baselineCompletionCount: dependency.baselineCompletionCount,
                createdAt: dependency.createdAt,
                updatedAt: tombstoneAt,
                deletedAt: tombstoneAt,
                serverRevision: dependency.serverRevision
            )
        }

        mergeDeletedDependencies(
            taskDependencies: [],
            recurringTaskDependencies: deletedRecurringTaskDependencies,
            shouldNotifySync: shouldNotifySync
        )
    }

    func getDirtyRewardTaskDependencies(ids: Set<RecordID>) -> [RewardTaskDependency] {
        rewardTaskDependencies.filter { ids.contains($0.id) }
    }

    func getDirtyRewardRecurringTaskDependencies(ids: Set<RecordID>) -> [RewardRecurringTaskDependency] {
        rewardRecurringTaskDependencies.filter { ids.contains($0.id) }
    }

    func persistReplacedAll(
        rewardTaskDependencies authoritativeRewardTaskDependencies: [RewardTaskDependency],
        rewardRecurringTaskDependencies authoritativeRewardRecurringTaskDependencies: [RewardRecurringTaskDependency]
    ) throws {
        let sortedTaskDependencies = OwnerScopedRecordSupport.sorted(authoritativeRewardTaskDependencies)
        let sortedRecurringTaskDependencies = OwnerScopedRecordSupport.sorted(authoritativeRewardRecurringTaskDependencies)
        try database.transaction(at: databaseURL) { db in
            try self.replaceRows(
                ownerID: self.currentOwnerID,
                rewardTaskDependencies: sortedTaskDependencies,
                rewardRecurringTaskDependencies: sortedRecurringTaskDependencies,
                on: db
            )
        }
        rewardTaskDependencies = sortedTaskDependencies
        rewardRecurringTaskDependencies = sortedRecurringTaskDependencies
    }

    func persistReplacedAll(
        rewardTaskDependencies authoritativeRewardTaskDependencies: [RewardTaskDependency],
        rewardRecurringTaskDependencies authoritativeRewardRecurringTaskDependencies: [RewardRecurringTaskDependency],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try replaceRows(
            ownerID: currentOwnerID,
            rewardTaskDependencies: OwnerScopedRecordSupport.sorted(authoritativeRewardTaskDependencies),
            rewardRecurringTaskDependencies: OwnerScopedRecordSupport.sorted(authoritativeRewardRecurringTaskDependencies),
            on: databaseHandle
        )
    }

    func deleteDependencies(
        rewardTaskDependencyIDs: Set<RecordID>,
        rewardRecurringTaskDependencyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try deleteDependencyRows(
            tableName: "reward_task_dependencies",
            keyColumnA: "reward_id",
            keyColumnB: "depends_on_task_id",
            ids: rewardTaskDependencyIDs,
            on: databaseHandle
        )
        try deleteDependencyRows(
            tableName: "reward_recurring_task_dependencies",
            keyColumnA: "reward_id",
            keyColumnB: "recurring_task_id",
            ids: rewardRecurringTaskDependencyIDs,
            on: databaseHandle
        )
    }

    func purgeDeleted(
        rewardTaskDependencyIDs dirtyRewardTaskDependencyIDs: Set<RecordID>,
        rewardRecurringTaskDependencyIDs dirtyRewardRecurringTaskDependencyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try purgeDeleted(tableName: "reward_task_dependencies", keyColumnA: "reward_id", keyColumnB: "depends_on_task_id", excluding: dirtyRewardTaskDependencyIDs, on: databaseHandle)
        try purgeDeleted(tableName: "reward_recurring_task_dependencies", keyColumnA: "reward_id", keyColumnB: "recurring_task_id", excluding: dirtyRewardRecurringTaskDependencyIDs, on: databaseHandle)
    }

    private func replaceRows(
        ownerID: String,
        rewardTaskDependencies: [RewardTaskDependency],
        rewardRecurringTaskDependencies: [RewardRecurringTaskDependency],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try database.execute("DELETE FROM reward_task_dependencies WHERE owner_id = ?", bindings: [.text(ownerID)], on: databaseHandle)
        try database.execute("DELETE FROM reward_recurring_task_dependencies WHERE owner_id = ?", bindings: [.text(ownerID)], on: databaseHandle)

        for dependency in rewardTaskDependencies {
            try database.execute(
                """
                INSERT INTO reward_task_dependencies (
                    owner_id, reward_id, depends_on_task_id, created_at, updated_at, deleted_at, server_revision
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: rewardTaskDependencyBindings(dependency, ownerID: ownerID),
                on: databaseHandle
            )
        }

        for dependency in rewardRecurringTaskDependencies {
            try database.execute(
                """
                INSERT INTO reward_recurring_task_dependencies (
                    owner_id, reward_id, recurring_task_id, required_completions, baseline_completion_count, created_at, updated_at, deleted_at, server_revision
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: rewardRecurringTaskDependencyBindings(dependency, ownerID: ownerID),
                on: databaseHandle
            )
        }
    }

    private func loadRewardTaskDependencies(ownerID: String) -> [RewardTaskDependency] {
        let fetched = (try? database.query(
            """
            SELECT reward_id, depends_on_task_id, created_at, updated_at, deleted_at, server_revision
            FROM reward_task_dependencies
            WHERE owner_id = ?
            ORDER BY created_at ASC, reward_id ASC, depends_on_task_id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            RewardTaskDependency(
                rewardId: RecordID(SQLiteColumn.text(row, index: 0)),
                dependsOnTaskId: RecordID(SQLiteColumn.text(row, index: 1)),
                createdAt: SQLiteColumn.date(row, index: 2),
                updatedAt: SQLiteColumn.date(row, index: 3),
                deletedAt: SQLiteColumn.optionalDate(row, index: 4),
                serverRevision: SQLiteColumn.optionalInt64(row, index: 5)
            )
        }) ?? []
        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func loadRewardRecurringTaskDependencies(ownerID: String) -> [RewardRecurringTaskDependency] {
        let fetched = (try? database.query(
            """
            SELECT reward_id, recurring_task_id, required_completions, baseline_completion_count, created_at, updated_at, deleted_at, server_revision
            FROM reward_recurring_task_dependencies
            WHERE owner_id = ?
            ORDER BY created_at ASC, reward_id ASC, recurring_task_id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            RewardRecurringTaskDependency(
                rewardId: RecordID(SQLiteColumn.text(row, index: 0)),
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
        rewardTaskDependencies = loadRewardTaskDependencies(ownerID: currentOwnerID)
        rewardRecurringTaskDependencies = loadRewardRecurringTaskDependencies(ownerID: currentOwnerID)
    }

    private func rewardTaskDependencyBindings(_ dependency: RewardTaskDependency, ownerID: String) -> [SQLiteValue] {
        [
            .text(ownerID),
            .text(dependency.rewardId.rawValue),
            .text(dependency.dependsOnTaskId.rawValue),
            .double(dependency.createdAt.timeIntervalSince1970),
            .double(dependency.updatedAt.timeIntervalSince1970),
            dependency.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            dependency.serverRevision.map { .int($0) } ?? .null
        ]
    }

    private func rewardRecurringTaskDependencyBindings(_ dependency: RewardRecurringTaskDependency, ownerID: String) -> [SQLiteValue] {
        [
            .text(ownerID),
            .text(dependency.rewardId.rawValue),
            .text(dependency.recurringTaskId.rawValue),
            .int(Int64(dependency.requiredCompletions)),
            .int(Int64(dependency.baselineCompletionCount)),
            .double(dependency.createdAt.timeIntervalSince1970),
            .double(dependency.updatedAt.timeIntervalSince1970),
            dependency.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            dependency.serverRevision.map { .int($0) } ?? .null
        ]
    }

    private func purgeDeleted(
        tableName: String,
        keyColumnA: String,
        keyColumnB: String,
        excluding dirtyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        if dirtyIDs.isEmpty {
            try database.execute("DELETE FROM \(tableName) WHERE owner_id = ? AND deleted_at IS NOT NULL", bindings: [.text(currentOwnerID)], on: databaseHandle)
            return
        }
        let pairs = dirtyIDs.map { pairColumns(for: $0) }
        let placeholders = Array(repeating: "(?, ?)", count: pairs.count).joined(separator: ", ")
        let bindings: [SQLiteValue] = [.text(currentOwnerID)] + pairs.flatMap { [.text($0.0.rawValue), .text($0.1.rawValue)] }
        try database.execute(
            "DELETE FROM \(tableName) WHERE owner_id = ? AND deleted_at IS NOT NULL AND (\(keyColumnA), \(keyColumnB)) NOT IN (\(placeholders))",
            bindings: bindings,
            on: databaseHandle
        )
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

    private func pairColumns(for id: RecordID) -> (RecordID, RecordID) {
        let parts = id.rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return (id, id) }
        return (RecordID(parts[0]), RecordID(parts[1]))
    }

    private func normalizedRewardTaskDependency(_ dependency: RewardTaskDependency, existing: RewardTaskDependency?) -> RewardTaskDependency {
        guard let existing else { return dependency }
        let updatedAt = dependency.updatedAt <= existing.updatedAt
            ? nextUpdatedAt(after: existing.updatedAt)
            : dependency.updatedAt
        return RewardTaskDependency(
            rewardId: dependency.rewardId,
            dependsOnTaskId: dependency.dependsOnTaskId,
            createdAt: dependency.createdAt,
            updatedAt: updatedAt,
            deletedAt: dependency.deletedAt,
            serverRevision: dependency.serverRevision ?? existing.serverRevision
        )
    }

    private func normalizedRewardRecurringTaskDependency(_ dependency: RewardRecurringTaskDependency, existing: RewardRecurringTaskDependency?) -> RewardRecurringTaskDependency {
        guard let existing else { return dependency }
        let updatedAt = dependency.updatedAt <= existing.updatedAt
            ? nextUpdatedAt(after: existing.updatedAt)
            : dependency.updatedAt
        return RewardRecurringTaskDependency(
            rewardId: dependency.rewardId,
            recurringTaskId: dependency.recurringTaskId,
            requiredCompletions: dependency.requiredCompletions,
            baselineCompletionCount: dependency.baselineCompletionCount,
            createdAt: dependency.createdAt,
            updatedAt: updatedAt,
            deletedAt: dependency.deletedAt,
            serverRevision: dependency.serverRevision ?? existing.serverRevision
        )
    }

    private func mergeDeletedDependencies(
        taskDependencies deletedTaskDependencies: [RewardTaskDependency],
        recurringTaskDependencies deletedRecurringTaskDependencies: [RewardRecurringTaskDependency],
        shouldNotifySync: Bool
    ) {
        guard !deletedTaskDependencies.isEmpty || !deletedRecurringTaskDependencies.isEmpty else { return }

        let mergedTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: rewardTaskDependencies,
            remote: deletedTaskDependencies
        )
        let mergedRecurringTaskDependencies = OwnerScopedRecordSupport.mergeRecords(
            local: rewardRecurringTaskDependencies,
            remote: deletedRecurringTaskDependencies
        )

        do {
            try persistReplacedAll(
                rewardTaskDependencies: mergedTaskDependencies,
                rewardRecurringTaskDependencies: mergedRecurringTaskDependencies
            )
        } catch {
            assertionFailure("Failed to delete reward dependencies: \(error)")
            return
        }

        guard shouldNotifySync else { return }
        markDirtyAndNotify(kind: .rewardTaskDependencies, ids: deletedTaskDependencies.map(\.id))
        markDirtyAndNotify(kind: .rewardRecurringTaskDependencies, ids: deletedRecurringTaskDependencies.map(\.id))
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
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: kind, recordIDs: ids))
    }
}
