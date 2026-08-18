import Foundation

// Sync flow: captures dirty record IDs at one moment so remote responses do
// not overwrite edits the user made while a sync was already running.
struct SyncDirtyIDSnapshot: Equatable {
    var timers: [RecordID: Int64] = [:]
    var tasks: [RecordID: Int64] = [:]
    var recurringTasks: [RecordID: Int64] = [:]
    var trades: [RecordID: Int64] = [:]
    var tags: [RecordID: Int64] = [:]
    var taskTags: [RecordID: Int64] = [:]
    var taskTaskDependencies: [RecordID: Int64] = [:]
    var taskRecurringTaskDependencies: [RecordID: Int64] = [:]
    var recurringTaskTags: [RecordID: Int64] = [:]
    var rewards: [RecordID: Int64] = [:]
    var rewardTaskDependencies: [RecordID: Int64] = [:]
    var rewardRecurringTaskDependencies: [RecordID: Int64] = [:]
    var rewardTags: [RecordID: Int64] = [:]

    static func from(_ state: SyncStateStore.UserSyncState) -> SyncDirtyIDSnapshot {
        SyncDirtyIDSnapshot(
            timers: Dictionary(uniqueKeysWithValues: state.dirty.timers.map { ($0.id, $0.generation) }),
            tasks: Dictionary(uniqueKeysWithValues: state.dirty.tasks.map { ($0.id, $0.generation) }),
            recurringTasks: Dictionary(uniqueKeysWithValues: state.dirty.recurringTasks.map { ($0.id, $0.generation) }),
            trades: Dictionary(uniqueKeysWithValues: state.dirty.trades.map { ($0.id, $0.generation) }),
            tags: Dictionary(uniqueKeysWithValues: state.dirty.tags.map { ($0.id, $0.generation) }),
            taskTags: Dictionary(uniqueKeysWithValues: state.dirty.taskTags.map { ($0.id, $0.generation) }),
            taskTaskDependencies: Dictionary(uniqueKeysWithValues: state.dirty.taskTaskDependencies.map { ($0.id, $0.generation) }),
            taskRecurringTaskDependencies: Dictionary(uniqueKeysWithValues: state.dirty.taskRecurringTaskDependencies.map { ($0.id, $0.generation) }),
            recurringTaskTags: Dictionary(uniqueKeysWithValues: state.dirty.recurringTaskTags.map { ($0.id, $0.generation) }),
            rewards: Dictionary(uniqueKeysWithValues: state.dirty.rewards.map { ($0.id, $0.generation) }),
            rewardTaskDependencies: Dictionary(uniqueKeysWithValues: state.dirty.rewardTaskDependencies.map { ($0.id, $0.generation) }),
            rewardRecurringTaskDependencies: Dictionary(uniqueKeysWithValues: state.dirty.rewardRecurringTaskDependencies.map { ($0.id, $0.generation) }),
            rewardTags: Dictionary(uniqueKeysWithValues: state.dirty.rewardTags.map { ($0.id, $0.generation) })
        )
    }

    static func changes(
        after current: SyncStateStore.UserSyncState,
        snapshot: SyncStateStore.UserSyncState
    ) -> SyncDirtyIDSnapshot {
        let currentIDs = SyncDirtyIDSnapshot.from(current)
        let snapshotIDs = SyncDirtyIDSnapshot.from(snapshot)

        return SyncDirtyIDSnapshot(
            timers: newerDirtyIDs(currentIDs.timers, than: snapshotIDs.timers),
            tasks: newerDirtyIDs(currentIDs.tasks, than: snapshotIDs.tasks),
            recurringTasks: newerDirtyIDs(currentIDs.recurringTasks, than: snapshotIDs.recurringTasks),
            trades: newerDirtyIDs(currentIDs.trades, than: snapshotIDs.trades),
            tags: newerDirtyIDs(currentIDs.tags, than: snapshotIDs.tags),
            taskTags: newerDirtyIDs(currentIDs.taskTags, than: snapshotIDs.taskTags),
            taskTaskDependencies: newerDirtyIDs(currentIDs.taskTaskDependencies, than: snapshotIDs.taskTaskDependencies),
            taskRecurringTaskDependencies: newerDirtyIDs(currentIDs.taskRecurringTaskDependencies, than: snapshotIDs.taskRecurringTaskDependencies),
            recurringTaskTags: newerDirtyIDs(currentIDs.recurringTaskTags, than: snapshotIDs.recurringTaskTags),
            rewards: newerDirtyIDs(currentIDs.rewards, than: snapshotIDs.rewards),
            rewardTaskDependencies: newerDirtyIDs(currentIDs.rewardTaskDependencies, than: snapshotIDs.rewardTaskDependencies),
            rewardRecurringTaskDependencies: newerDirtyIDs(currentIDs.rewardRecurringTaskDependencies, than: snapshotIDs.rewardRecurringTaskDependencies),
            rewardTags: newerDirtyIDs(currentIDs.rewardTags, than: snapshotIDs.rewardTags)
        )
    }

    private static func newerDirtyIDs(
        _ current: [RecordID: Int64],
        than snapshot: [RecordID: Int64]
    ) -> [RecordID: Int64] {
        current.filter { id, generation in
            snapshot[id] != generation
        }
    }
}
