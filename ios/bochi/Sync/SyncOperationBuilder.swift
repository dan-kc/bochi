import CryptoKit
import Foundation

// Sync flow: converts dirty local records into deterministic backend operations
// so retries and resumed runs keep stable operation IDs.
enum SyncOperationBuilder {
    static func makeUpsertOperations(from localState: SyncLocalState) -> [SyncOperation] {
        makeUpsertOperations(
            timers: localState.dirtyTimers,
            tasks: localState.dirtyTasks,
            taskTaskDependencies: localState.dirtyTaskTaskDependencies,
            taskRecurringTaskDependencies: localState.dirtyTaskRecurringTaskDependencies,
            recurringTasks: localState.dirtyRecurringTasks,
            trades: localState.dirtyTrades,
            tags: localState.dirtyTags,
            taskTags: localState.dirtyTaskTags,
            recurringTaskTags: localState.dirtyRecurringTaskTags,
            rewards: localState.dirtyRewards,
            rewardTaskDependencies: localState.dirtyRewardTaskDependencies,
            rewardRecurringTaskDependencies: localState.dirtyRewardRecurringTaskDependencies,
            rewardTags: localState.dirtyRewardTags,
            dirtySnapshot: localState.dirtySnapshot
        )
    }

    static func makeUpsertOperations(
        timers: [BochiTimer],
        tasks: [TaskItem],
        taskTaskDependencies: [TaskTaskDependency],
        taskRecurringTaskDependencies: [TaskRecurringTaskDependency],
        recurringTasks: [RecurringTask],
        trades: [Trade],
        tags: [Tag],
        taskTags: [TaskTag],
        recurringTaskTags: [RecurringTaskTag],
        rewards: [Reward],
        rewardTaskDependencies: [RewardTaskDependency],
        rewardRecurringTaskDependencies: [RewardRecurringTaskDependency],
        rewardTags: [RewardTag],
        dirtySnapshot: SyncDirtyIDSnapshot
    ) -> [SyncOperation] {
        let timerOperations = makeOperations(
            records: timers,
            entityKind: "timer",
            kind: "upsertTimer",
            dirtyGenerations: dirtySnapshot.timers,
            payload: { .timer(SyncTimerRecord.from($0)) }
        )
        let taskOperations = makeOperations(
            records: tasks,
            entityKind: "task",
            kind: "upsertTask",
            dirtyGenerations: dirtySnapshot.tasks,
            payload: { .task(SyncTaskRecord.from($0)) }
        )
        let taskTaskDependencyOperations = makeOperations(
            records: taskTaskDependencies,
            entityKind: "taskTaskDependency",
            kind: "upsertTaskTaskDependency",
            dirtyGenerations: dirtySnapshot.taskTaskDependencies,
            payload: { .taskTaskDependency(SyncTaskTaskDependencyRecord.from($0)) }
        )
        let taskRecurringTaskDependencyOperations = makeOperations(
            records: taskRecurringTaskDependencies,
            entityKind: "taskRecurringTaskDependency",
            kind: "upsertTaskRecurringTaskDependency",
            dirtyGenerations: dirtySnapshot.taskRecurringTaskDependencies,
            payload: { .taskRecurringTaskDependency(SyncTaskRecurringTaskDependencyRecord.from($0)) }
        )
        let recurringTaskOperations = makeOperations(
            records: recurringTasks,
            entityKind: "recurringTask",
            kind: "upsertRecurringTask",
            dirtyGenerations: dirtySnapshot.recurringTasks,
            payload: { .recurringTask(SyncRecurringTaskRecord.from($0)) }
        )
        let tradeOperations = makeOperations(
            records: trades,
            entityKind: "trade",
            kind: "upsertTrade",
            dirtyGenerations: dirtySnapshot.trades,
            payload: { .trade(SyncTradeRecord.from($0)) }
        )
        let tagOperations = makeOperations(
            records: tags,
            entityKind: "tag",
            kind: "upsertTag",
            dirtyGenerations: dirtySnapshot.tags,
            payload: { .tag(SyncTagRecord.from($0)) }
        )
        let taskTagOperations = makeOperations(
            records: taskTags,
            entityKind: "taskTag",
            kind: "upsertTaskTag",
            dirtyGenerations: dirtySnapshot.taskTags,
            payload: { .taskTag(SyncTaskTagRecord.from($0)) }
        )
        let recurringTaskTagOperations = makeOperations(
            records: recurringTaskTags,
            entityKind: "recurringTaskTag",
            kind: "upsertRecurringTaskTag",
            dirtyGenerations: dirtySnapshot.recurringTaskTags,
            payload: { .recurringTaskTag(SyncRecurringTaskTagRecord.from($0)) }
        )
        let rewardOperations = makeOperations(
            records: rewards,
            entityKind: "reward",
            kind: "upsertReward",
            dirtyGenerations: dirtySnapshot.rewards,
            payload: { .reward(SyncRewardRecord.from($0)) }
        )
        let rewardTaskDependencyOperations = makeOperations(
            records: rewardTaskDependencies,
            entityKind: "rewardTaskDependency",
            kind: "upsertRewardTaskDependency",
            dirtyGenerations: dirtySnapshot.rewardTaskDependencies,
            payload: { .rewardTaskDependency(SyncRewardTaskDependencyRecord.from($0)) }
        )
        let rewardRecurringTaskDependencyOperations = makeOperations(
            records: rewardRecurringTaskDependencies,
            entityKind: "rewardRecurringTaskDependency",
            kind: "upsertRewardRecurringTaskDependency",
            dirtyGenerations: dirtySnapshot.rewardRecurringTaskDependencies,
            payload: { .rewardRecurringTaskDependency(SyncRewardRecurringTaskDependencyRecord.from($0)) }
        )
        let rewardTagOperations = makeOperations(
            records: rewardTags,
            entityKind: "rewardTag",
            kind: "upsertRewardTag",
            dirtyGenerations: dirtySnapshot.rewardTags,
            payload: { .rewardTag(SyncRewardTagRecord.from($0)) }
        )

        return timerOperations
            + taskOperations
            + taskTaskDependencyOperations
            + taskRecurringTaskDependencyOperations
            + recurringTaskOperations
            + tradeOperations
            + tagOperations
            + taskTagOperations
            + recurringTaskTagOperations
            + rewardOperations
            + rewardTaskDependencyOperations
            + rewardRecurringTaskDependencyOperations
            + rewardTagOperations
    }

    static func makeThemePalettesOperation(
        themePalettes: SyncThemePalettes,
        generation: Int64
    ) -> SyncOperation {
        SyncOperation(
            operationId: operationID(
                entityKind: "themePalettes",
                recordID: RecordID("themePalettes"),
                generation: generation
            ),
            kind: "updateThemePalettes",
            baseRecordRevision: nil,
            payload: .themePalettes(themePalettes)
        )
    }

    static func operationID(entityKind: String, recordID: RecordID, generation: Int64) -> UUID {
        let input = "bochi-sync-operation:\(entityKind):\(recordID.rawValue):\(generation)"
        let digest = SHA256.hash(data: Data(input.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func makeOperations<Record>(
        records: [Record],
        entityKind: String,
        kind: String,
        dirtyGenerations: [RecordID: Int64],
        payload: (Record) -> SyncOperationPayload
    ) -> [SyncOperation] where Record: OwnerScopedSyncRecord {
        records.map { record in
            SyncOperation(
                operationId: operationID(
                    entityKind: entityKind,
                    recordID: record.id,
                    generation: dirtyGenerations[record.id] ?? 0
                ),
                kind: kind,
                baseRecordRevision: record.serverRevision,
                payload: payload(record)
            )
        }
    }
}

private protocol OwnerScopedSyncRecord: OwnerScopedRecord {
    var serverRevision: Int64? { get }
}

extension BochiTimer: OwnerScopedSyncRecord {}
extension RecurringTask: OwnerScopedSyncRecord {}
extension Reward: OwnerScopedSyncRecord {}
extension RewardRecurringTaskDependency: OwnerScopedSyncRecord {}
extension RewardTag: OwnerScopedSyncRecord {}
extension RewardTaskDependency: OwnerScopedSyncRecord {}
extension Tag: OwnerScopedSyncRecord {}
extension TaskItem: OwnerScopedSyncRecord {}
extension RecurringTaskTag: OwnerScopedSyncRecord {}
extension TaskRecurringTaskDependency: OwnerScopedSyncRecord {}
extension TaskTag: OwnerScopedSyncRecord {}
extension TaskTaskDependency: OwnerScopedSyncRecord {}
extension Trade: OwnerScopedSyncRecord {}
