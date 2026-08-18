import Foundation

// Sync flow: commits a successful run by advancing the cursor and clearing
// only the dirty generations captured at the start of that run.
@MainActor
struct SyncCompletionFinalizer {
    private let syncStateStore: SyncStateStore
    private let timerStore: TimerStore
    private let taskStore: TaskStore
    private let taskDependencyStore: TaskDependencyStore
    private let rewardDependencyStore: RewardDependencyStore
    private let recurringTaskStore: RecurringTaskStore
    private let rewardStore: RewardStore
    private let tradeStore: TradeStore
    private let tagStore: TagStore

    init(
        syncStateStore: SyncStateStore,
        timerStore: TimerStore,
        taskStore: TaskStore,
        taskDependencyStore: TaskDependencyStore,
        rewardDependencyStore: RewardDependencyStore,
        recurringTaskStore: RecurringTaskStore,
        rewardStore: RewardStore,
        tradeStore: TradeStore,
        tagStore: TagStore
    ) {
        self.syncStateStore = syncStateStore
        self.timerStore = timerStore
        self.taskStore = taskStore
        self.taskDependencyStore = taskDependencyStore
        self.rewardDependencyStore = rewardDependencyStore
        self.recurringTaskStore = recurringTaskStore
        self.rewardStore = rewardStore
        self.tradeStore = tradeStore
        self.tagStore = tagStore
    }

    func finalizeSuccessfulSync(
        userID: String,
        syncStateSnapshot: SyncStateStore.UserSyncState,
        checkpointResponse: SyncResponse,
        localState: SyncLocalState,
        completedFullSync: Bool
    ) throws -> Date {
        let serverTime = AppDateCoding.parseBackendTimestamp(checkpointResponse.serverTime) ?? Date()

        try AppDatabase.shared.transaction(at: syncStateStore.databaseURL) { db in
            // User edits made while the network request is in flight should
            // remain dirty for the next sync. The snapshot is the generation set
            // that was applied by this run, so later generations survive.
            try syncStateStore.completeSync(
                userID: userID,
                snapshot: syncStateSnapshot,
                serverCursor: checkpointResponse.serverCursor,
                serverTime: serverTime,
                completedFullSync: completedFullSync,
                on: db
            )
            try tagStore.deleteTagAssociations(
                taskTagIDs: localState.invalidDirtyTaskTagIDs,
                recurringTaskTagIDs: localState.invalidDirtyRecurringTaskTagIDs,
                rewardTagIDs: localState.invalidDirtyRewardTagIDs,
                on: db
            )
            try taskDependencyStore.deleteDependencies(
                taskTaskDependencyIDs: localState.invalidDirtyTaskTaskDependencyIDs,
                taskRecurringTaskDependencyIDs: localState.invalidDirtyTaskRecurringTaskDependencyIDs,
                on: db
            )
            try rewardDependencyStore.deleteDependencies(
                rewardTaskDependencyIDs: localState.invalidDirtyRewardTaskDependencyIDs,
                rewardRecurringTaskDependencyIDs: localState.invalidDirtyRewardRecurringTaskDependencyIDs,
                on: db
            )

            let remainingDirty = try syncStateStore.state(for: userID, on: db)
            try purgeSyncedTombstones(preserving: remainingDirty, on: db)
        }

        return serverTime
    }

    private func purgeSyncedTombstones(
        preserving remainingDirty: SyncStateStore.UserSyncState,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try timerStore.purgeDeletedTimers(
            excluding: Set(remainingDirty.dirty.timers.map(\.id)),
            on: databaseHandle
        )
        try taskStore.purgeDeletedTasks(
            excluding: Set(remainingDirty.dirty.tasks.map(\.id)),
            on: databaseHandle
        )
        try taskDependencyStore.purgeDeleted(
            taskTaskDependencyIDs: Set(remainingDirty.dirty.taskTaskDependencies.map(\.id)),
            taskRecurringTaskDependencyIDs: Set(remainingDirty.dirty.taskRecurringTaskDependencies.map(\.id)),
            on: databaseHandle
        )
        try recurringTaskStore.purgeDeletedRecurringTasks(
            excluding: Set(remainingDirty.dirty.recurringTasks.map(\.id)),
            on: databaseHandle
        )
        try tradeStore.purgeDeletedTrades(
            excluding: Set(remainingDirty.dirty.trades.map(\.id)),
            on: databaseHandle
        )
        try tagStore.purgeDeleted(
            excludingTagIDs: Set(remainingDirty.dirty.tags.map(\.id)),
            taskTagIDs: Set(remainingDirty.dirty.taskTags.map(\.id)),
            recurringTaskTagIDs: Set(remainingDirty.dirty.recurringTaskTags.map(\.id)),
            rewardTagIDs: Set(remainingDirty.dirty.rewardTags.map(\.id)),
            on: databaseHandle
        )
        try rewardStore.purgeDeletedRewards(
            excluding: Set(remainingDirty.dirty.rewards.map(\.id)),
            on: databaseHandle
        )
        try rewardDependencyStore.purgeDeleted(
            rewardTaskDependencyIDs: Set(remainingDirty.dirty.rewardTaskDependencies.map(\.id)),
            rewardRecurringTaskDependencyIDs: Set(remainingDirty.dirty.rewardRecurringTaskDependencies.map(\.id)),
            on: databaseHandle
        )
    }
}
