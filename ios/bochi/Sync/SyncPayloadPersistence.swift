import Foundation

// Sync flow: reads and writes the current owner's sync payload in one database
// transaction, then refreshes owner-scoped stores from that persisted state.
@MainActor
struct SyncPayloadPersistence {
    private let syncStateStore: SyncStateStore
    private let timerStore: TimerStore
    private let taskStore: TaskStore
    private let taskDependencyStore: TaskDependencyStore
    private let rewardDependencyStore: RewardDependencyStore
    private let recurringTaskStore: RecurringTaskStore
    private let rewardStore: RewardStore
    private let tradeStore: TradeStore
    private let tagStore: TagStore
    private let ownerScopeCoordinator: OwnerScopeCoordinator

    init(
        syncStateStore: SyncStateStore,
        timerStore: TimerStore,
        taskStore: TaskStore,
        taskDependencyStore: TaskDependencyStore,
        rewardDependencyStore: RewardDependencyStore,
        recurringTaskStore: RecurringTaskStore,
        rewardStore: RewardStore,
        tradeStore: TradeStore,
        tagStore: TagStore,
        ownerScopeCoordinator: OwnerScopeCoordinator
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
        self.ownerScopeCoordinator = ownerScopeCoordinator
    }

    func currentPayload() -> SyncPayload {
        SyncPayload(
            timers: timerStore.timers,
            tasks: taskStore.tasks,
            taskTaskDependencies: taskDependencyStore.taskTaskDependencies,
            taskRecurringTaskDependencies: taskDependencyStore.taskRecurringTaskDependencies,
            recurringTasks: recurringTaskStore.recurringTasks,
            trades: tradeStore.trades,
            tags: tagStore.tags,
            taskTags: tagStore.taskTags,
            recurringTaskTags: tagStore.recurringTaskTags,
            rewards: rewardStore.rewards,
            rewardTaskDependencies: rewardDependencyStore.rewardTaskDependencies,
            rewardRecurringTaskDependencies: rewardDependencyStore.rewardRecurringTaskDependencies,
            rewardTags: tagStore.rewardTags
        )
    }

    func mergedCurrentPayload(with incoming: SyncPayload) -> SyncPayload {
        let current = currentPayload()
        return SyncPayload(
            timers: merge(current: current.timers, incoming: incoming.timers),
            tasks: merge(current: current.tasks, incoming: incoming.tasks),
            taskTaskDependencies: merge(
                current: current.taskTaskDependencies,
                incoming: incoming.taskTaskDependencies
            ),
            taskRecurringTaskDependencies: merge(
                current: current.taskRecurringTaskDependencies,
                incoming: incoming.taskRecurringTaskDependencies
            ),
            recurringTasks: merge(current: current.recurringTasks, incoming: incoming.recurringTasks),
            trades: merge(current: current.trades, incoming: incoming.trades),
            tags: merge(current: current.tags, incoming: incoming.tags),
            taskTags: merge(current: current.taskTags, incoming: incoming.taskTags),
            recurringTaskTags: merge(current: current.recurringTaskTags, incoming: incoming.recurringTaskTags),
            rewards: merge(current: current.rewards, incoming: incoming.rewards),
            rewardTaskDependencies: merge(
                current: current.rewardTaskDependencies,
                incoming: incoming.rewardTaskDependencies
            ),
            rewardRecurringTaskDependencies: merge(
                current: current.rewardRecurringTaskDependencies,
                incoming: incoming.rewardRecurringTaskDependencies
            ),
            rewardTags: merge(current: current.rewardTags, incoming: incoming.rewardTags)
        )
    }

    func persist(_ payload: SyncPayload, ownerID: String) throws {
        try AppDatabase.shared.transaction(at: syncStateStore.databaseURL) { db in
            try timerStore.replaceTimers(payload.timers, on: db)
            try taskStore.replaceTasks(payload.tasks, on: db)
            try taskDependencyStore.persistReplacedAll(
                taskTaskDependencies: payload.taskTaskDependencies,
                taskRecurringTaskDependencies: payload.taskRecurringTaskDependencies,
                on: db
            )
            try recurringTaskStore.replaceRecurringTasks(payload.recurringTasks, on: db)
            try tradeStore.replaceTrades(payload.trades, on: db)
            try tagStore.replaceAll(
                tags: payload.tags,
                taskTags: payload.taskTags,
                recurringTaskTags: payload.recurringTaskTags,
                rewardTags: payload.rewardTags,
                on: db
            )
            try rewardStore.replaceRewards(payload.rewards, on: db)
            try rewardDependencyStore.persistReplacedAll(
                rewardTaskDependencies: payload.rewardTaskDependencies,
                rewardRecurringTaskDependencies: payload.rewardRecurringTaskDependencies,
                on: db
            )
        }
        ownerScopeCoordinator.setCurrentOwner(ownerID)
    }

    private func merge<Record: OwnerScopedRecord>(
        current: [Record],
        incoming: [Record]
    ) -> [Record] {
        incoming.isEmpty
            ? current
            : OwnerScopedRecordSupport.applyingAuthoritativeRecords(local: current, remote: incoming)
    }
}
