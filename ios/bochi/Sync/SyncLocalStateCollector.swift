import Foundation

// Sync flow: reads the dirty local records that must be preserved during pull
// and sent back to the server during a manual sync.
struct SyncLocalState {
    let dirtySnapshot: SyncDirtyIDSnapshot
    let dirtyTimers: [BochiTimer]
    let dirtyTasks: [TaskItem]
    let dirtyTaskTaskDependencies: [TaskTaskDependency]
    let dirtyTaskRecurringTaskDependencies: [TaskRecurringTaskDependency]
    let dirtyRecurringTasks: [RecurringTask]
    let dirtyTrades: [Trade]
    let dirtyTags: [Tag]
    let dirtyTaskTags: [TaskTag]
    let dirtyRecurringTaskTags: [RecurringTaskTag]
    let dirtyRewards: [Reward]
    let dirtyRewardTaskDependencies: [RewardTaskDependency]
    let dirtyRewardRecurringTaskDependencies: [RewardRecurringTaskDependency]
    let dirtyRewardTags: [RewardTag]
    let localDraftTaskTags: [TaskTag]
    let localDraftRecurringTaskTags: [RecurringTaskTag]
    let localDraftRewardTags: [RewardTag]
    let invalidDirtyTaskTagIDs: Set<RecordID>
    let invalidDirtyRecurringTaskTagIDs: Set<RecordID>
    let invalidDirtyRewardTagIDs: Set<RecordID>
    let invalidDirtyTaskTaskDependencyIDs: Set<RecordID>
    let invalidDirtyTaskRecurringTaskDependencyIDs: Set<RecordID>
    let invalidDirtyRewardTaskDependencyIDs: Set<RecordID>
    let invalidDirtyRewardRecurringTaskDependencyIDs: Set<RecordID>
    let themePalettesDirty: Bool

    var hasDirtyChanges: Bool {
        !dirtyTimers.isEmpty
            || !dirtyTasks.isEmpty
            || !dirtyTaskTaskDependencies.isEmpty
            || !dirtyTaskRecurringTaskDependencies.isEmpty
            || !dirtyRecurringTasks.isEmpty
            || !dirtyTrades.isEmpty
            || !dirtyTags.isEmpty
            || !dirtyTaskTags.isEmpty
            || !dirtyRecurringTaskTags.isEmpty
            || !dirtyRewards.isEmpty
            || !dirtyRewardTaskDependencies.isEmpty
            || !dirtyRewardRecurringTaskDependencies.isEmpty
            || !dirtyRewardTags.isEmpty
            || themePalettesDirty
    }
}

@MainActor
struct SyncLocalStateCollector {
    private let timerStore: TimerStore
    private let taskStore: TaskStore
    private let taskDependencyStore: TaskDependencyStore
    private let rewardDependencyStore: RewardDependencyStore
    private let recurringTaskStore: RecurringTaskStore
    private let rewardStore: RewardStore
    private let tradeStore: TradeStore
    private let tagStore: TagStore

    init(
        timerStore: TimerStore,
        taskStore: TaskStore,
        taskDependencyStore: TaskDependencyStore,
        rewardDependencyStore: RewardDependencyStore,
        recurringTaskStore: RecurringTaskStore,
        rewardStore: RewardStore,
        tradeStore: TradeStore,
        tagStore: TagStore
    ) {
        self.timerStore = timerStore
        self.taskStore = taskStore
        self.taskDependencyStore = taskDependencyStore
        self.rewardDependencyStore = rewardDependencyStore
        self.recurringTaskStore = recurringTaskStore
        self.rewardStore = rewardStore
        self.tradeStore = tradeStore
        self.tagStore = tagStore
    }

    func collect(from syncState: SyncStateStore.UserSyncState) -> SyncLocalState {
        let dirtySnapshot = SyncDirtyIDSnapshot.from(syncState)
        let localIDs = SyncLocalRecordIDs(
            taskIDs: Set(taskStore.tasks.map(\.id)),
            recurringTaskIDs: Set(recurringTaskStore.recurringTasks.map(\.id)),
            rewardIDs: Set(rewardStore.rewards.map(\.id)),
            tagIDs: Set(tagStore.tags.map(\.id))
        )
        let dirtyTaskTaskDependencyRows = taskDependencyStore.getDirtyTaskTaskDependencies(
            ids: Set(dirtySnapshot.taskTaskDependencies.keys)
        )
        let dirtyTaskTaskDependencies = validTaskTaskDependenciesForSync(
            dirtyTaskTaskDependencyRows,
            localIDs: localIDs
        )
        let dirtyTaskRecurringTaskDependencyRows = taskDependencyStore.getDirtyTaskRecurringTaskDependencies(
            ids: Set(dirtySnapshot.taskRecurringTaskDependencies.keys)
        )
        let dirtyTaskRecurringTaskDependencies = validTaskRecurringTaskDependenciesForSync(
            dirtyTaskRecurringTaskDependencyRows,
            localIDs: localIDs
        )
        let dirtyTaskTagRows = tagStore.getDirtyTaskTags(ids: Set(dirtySnapshot.taskTags.keys))
        let dirtyTaskTags = validTaskTagsForSync(dirtyTaskTagRows, localIDs: localIDs)
        let dirtyRecurringTaskTagRows = tagStore.getDirtyRecurringTaskTags(ids: Set(dirtySnapshot.recurringTaskTags.keys))
        let dirtyRecurringTaskTags = validRecurringTaskTagsForSync(dirtyRecurringTaskTagRows, localIDs: localIDs)
        let dirtyRewardTaskDependencyRows = rewardDependencyStore.getDirtyRewardTaskDependencies(
            ids: Set(dirtySnapshot.rewardTaskDependencies.keys)
        )
        let dirtyRewardTaskDependencies = validRewardTaskDependenciesForSync(
            dirtyRewardTaskDependencyRows,
            localIDs: localIDs
        )
        let dirtyRewardRecurringTaskDependencyRows = rewardDependencyStore.getDirtyRewardRecurringTaskDependencies(
            ids: Set(dirtySnapshot.rewardRecurringTaskDependencies.keys)
        )
        let dirtyRewardRecurringTaskDependencies = validRewardRecurringTaskDependenciesForSync(
            dirtyRewardRecurringTaskDependencyRows,
            localIDs: localIDs
        )
        let dirtyRewardTagRows = tagStore.getDirtyRewardTags(ids: Set(dirtySnapshot.rewardTags.keys))
        let dirtyRewardTags = validRewardTagsForSync(dirtyRewardTagRows, localIDs: localIDs)

        return SyncLocalState(
            dirtySnapshot: dirtySnapshot,
            dirtyTimers: timerStore.getDirtyTimers(ids: Set(dirtySnapshot.timers.keys)),
            dirtyTasks: taskStore.getDirtyTasks(ids: Set(dirtySnapshot.tasks.keys)),
            dirtyTaskTaskDependencies: dirtyTaskTaskDependencies,
            dirtyTaskRecurringTaskDependencies: dirtyTaskRecurringTaskDependencies,
            dirtyRecurringTasks: recurringTaskStore.getDirtyRecurringTasks(ids: Set(dirtySnapshot.recurringTasks.keys)),
            dirtyTrades: tradeStore.getDirtyTrades(ids: Set(dirtySnapshot.trades.keys)),
            dirtyTags: tagStore.getDirtyTags(ids: Set(dirtySnapshot.tags.keys)),
            dirtyTaskTags: dirtyTaskTags,
            dirtyRecurringTaskTags: dirtyRecurringTaskTags,
            dirtyRewards: rewardStore.getDirtyRewards(ids: Set(dirtySnapshot.rewards.keys)),
            dirtyRewardTaskDependencies: dirtyRewardTaskDependencies,
            dirtyRewardRecurringTaskDependencies: dirtyRewardRecurringTaskDependencies,
            dirtyRewardTags: dirtyRewardTags,
            localDraftTaskTags: localDraftTaskTagsForFullSync(
                excludingDirtyIDs: dirtySnapshot.taskTags,
                localIDs: localIDs
            ),
            localDraftRecurringTaskTags: localDraftRecurringTaskTagsForFullSync(
                excludingDirtyIDs: dirtySnapshot.recurringTaskTags,
                localIDs: localIDs
            ),
            localDraftRewardTags: localDraftRewardTagsForFullSync(
                excludingDirtyIDs: dirtySnapshot.rewardTags,
                localIDs: localIDs
            ),
            invalidDirtyTaskTagIDs: invalidDirtyIDs(all: dirtyTaskTagRows, valid: dirtyTaskTags),
            invalidDirtyRecurringTaskTagIDs: invalidDirtyIDs(
                all: dirtyRecurringTaskTagRows,
                valid: dirtyRecurringTaskTags
            ),
            invalidDirtyRewardTagIDs: invalidDirtyIDs(all: dirtyRewardTagRows, valid: dirtyRewardTags),
            invalidDirtyTaskTaskDependencyIDs: invalidDirtyIDs(
                all: dirtyTaskTaskDependencyRows,
                valid: dirtyTaskTaskDependencies
            ),
            invalidDirtyTaskRecurringTaskDependencyIDs: invalidDirtyIDs(
                all: dirtyTaskRecurringTaskDependencyRows,
                valid: dirtyTaskRecurringTaskDependencies
            ),
            invalidDirtyRewardTaskDependencyIDs: invalidDirtyIDs(
                all: dirtyRewardTaskDependencyRows,
                valid: dirtyRewardTaskDependencies
            ),
            invalidDirtyRewardRecurringTaskDependencyIDs: invalidDirtyIDs(
                all: dirtyRewardRecurringTaskDependencyRows,
                valid: dirtyRewardRecurringTaskDependencies
            ),
            themePalettesDirty: syncState.dirty.themePalettes
        )
    }

    private func validTaskTagsForSync(
        _ taskTags: [TaskTag],
        localIDs: SyncLocalRecordIDs
    ) -> [TaskTag] {
        taskTags.filter {
            localIDs.taskIDs.contains($0.taskId) && localIDs.tagIDs.contains($0.tagId)
        }
    }

    private func validRecurringTaskTagsForSync(
        _ recurringTaskTags: [RecurringTaskTag],
        localIDs: SyncLocalRecordIDs
    ) -> [RecurringTaskTag] {
        recurringTaskTags.filter {
            localIDs.recurringTaskIDs.contains($0.recurringTaskId) && localIDs.tagIDs.contains($0.tagId)
        }
    }

    private func validRewardTagsForSync(
        _ rewardTags: [RewardTag],
        localIDs: SyncLocalRecordIDs
    ) -> [RewardTag] {
        rewardTags.filter {
            localIDs.rewardIDs.contains($0.rewardId) && localIDs.tagIDs.contains($0.tagId)
        }
    }

    private func validRewardTaskDependenciesForSync(
        _ dependencies: [RewardTaskDependency],
        localIDs: SyncLocalRecordIDs
    ) -> [RewardTaskDependency] {
        dependencies.filter {
            localIDs.rewardIDs.contains($0.rewardId) && localIDs.taskIDs.contains($0.dependsOnTaskId)
        }
    }

    private func validRewardRecurringTaskDependenciesForSync(
        _ dependencies: [RewardRecurringTaskDependency],
        localIDs: SyncLocalRecordIDs
    ) -> [RewardRecurringTaskDependency] {
        dependencies.filter {
            localIDs.rewardIDs.contains($0.rewardId)
                && localIDs.recurringTaskIDs.contains($0.recurringTaskId)
                && $0.requiredCompletions > 0
                && $0.baselineCompletionCount >= 0
        }
    }

    private func validTaskTaskDependenciesForSync(
        _ dependencies: [TaskTaskDependency],
        localIDs: SyncLocalRecordIDs
    ) -> [TaskTaskDependency] {
        dependencies.filter { dependency in
            guard localIDs.taskIDs.contains(dependency.taskId),
                localIDs.taskIDs.contains(dependency.dependsOnTaskId)
            else {
                return false
            }
            guard dependency.deletedAt == nil else { return true }
            guard dependency.taskId != dependency.dependsOnTaskId else { return false }
            return !wouldCreateTaskDependencyCycle(dependency)
        }
    }

    private func validTaskRecurringTaskDependenciesForSync(
        _ dependencies: [TaskRecurringTaskDependency],
        localIDs: SyncLocalRecordIDs
    ) -> [TaskRecurringTaskDependency] {
        dependencies.filter {
            localIDs.taskIDs.contains($0.taskId)
                && localIDs.recurringTaskIDs.contains($0.recurringTaskId)
                && $0.requiredCompletions > 0
                && $0.baselineCompletionCount >= 0
        }
    }

    private func wouldCreateTaskDependencyCycle(_ dependency: TaskTaskDependency) -> Bool {
        var graph: [RecordID: Set<RecordID>] = [:]
        for row in taskDependencyStore.taskTaskDependencies {
            guard row.deletedAt == nil, row.id != dependency.id else { continue }
            graph[row.taskId, default: []].insert(row.dependsOnTaskId)
        }

        var stack = [dependency.dependsOnTaskId]
        var visited: Set<RecordID> = []
        while let current = stack.popLast() {
            guard visited.insert(current).inserted else { continue }
            guard current != dependency.taskId else { return true }
            stack.append(contentsOf: graph[current] ?? [])
        }
        return false
    }

    private func invalidDirtyIDs<T: Identifiable>(
        all rows: [T],
        valid validRows: [T]
    ) -> Set<RecordID> where T.ID == RecordID {
        Set(rows.map(\.id)).subtracting(validRows.map(\.id))
    }

    private func localDraftTaskTagsForFullSync(
        excludingDirtyIDs dirtyIDs: [RecordID: Int64],
        localIDs: SyncLocalRecordIDs
    ) -> [TaskTag] {
        tagStore.taskTags.filter {
            dirtyIDs[$0.id] == nil
                && $0.deletedAt == nil
                && !localIDs.taskIDs.contains($0.taskId)
                && localIDs.tagIDs.contains($0.tagId)
        }
    }

    private func localDraftRecurringTaskTagsForFullSync(
        excludingDirtyIDs dirtyIDs: [RecordID: Int64],
        localIDs: SyncLocalRecordIDs
    ) -> [RecurringTaskTag] {
        tagStore.recurringTaskTags.filter {
            dirtyIDs[$0.id] == nil
                && $0.deletedAt == nil
                && !localIDs.recurringTaskIDs.contains($0.recurringTaskId)
                && localIDs.tagIDs.contains($0.tagId)
        }
    }

    private func localDraftRewardTagsForFullSync(
        excludingDirtyIDs dirtyIDs: [RecordID: Int64],
        localIDs: SyncLocalRecordIDs
    ) -> [RewardTag] {
        tagStore.rewardTags.filter {
            dirtyIDs[$0.id] == nil
                && $0.deletedAt == nil
                && !localIDs.rewardIDs.contains($0.rewardId)
                && localIDs.tagIDs.contains($0.tagId)
        }
    }
}

private struct SyncLocalRecordIDs {
    let taskIDs: Set<RecordID>
    let recurringTaskIDs: Set<RecordID>
    let rewardIDs: Set<RecordID>
    let tagIDs: Set<RecordID>
}
