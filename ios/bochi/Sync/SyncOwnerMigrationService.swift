import Foundation

// Sync flow: when a local user signs in, this moves local-device rows into the
// account owner and marks them dirty for the first upload.
@MainActor
struct SyncOwnerMigrationService {
    private let syncStateStore: SyncStateStore
    private let timerStore: TimerStore
    private let taskStore: TaskStore
    private let taskDependencyStore: TaskDependencyStore
    private let rewardDependencyStore: RewardDependencyStore
    private let recurringTaskStore: RecurringTaskStore
    private let rewardStore: RewardStore
    private let tradeStore: TradeStore
    private let tagStore: TagStore
    private let userSettingsStore: UserSettingsStore
    private let reminderStore: ReminderStore
    private let listPreferencesStore: ListPreferencesStore

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
        userSettingsStore: UserSettingsStore,
        reminderStore: ReminderStore,
        listPreferencesStore: ListPreferencesStore
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
        self.userSettingsStore = userSettingsStore
        self.reminderStore = reminderStore
        self.listPreferencesStore = listPreferencesStore
    }

    func migrateLocalData(to userID: String) throws {
        runMigrationStep("timers", to: userID) { db in
            let migratedTimerIDs = try timerStore.migrateTimers(from: StorageOwner.local, to: userID, on: db)
            if !migratedTimerIDs.isEmpty {
                try syncStateStore.markDirty(userID: userID, kind: .timers, ids: migratedTimerIDs, on: db)
            }
        }

        runMigrationStep("tasks", to: userID) { db in
            let migratedTaskIDs = try taskStore.migrateTasks(from: StorageOwner.local, to: userID, on: db)
            if !migratedTaskIDs.isEmpty {
                try syncStateStore.markDirty(userID: userID, kind: .tasks, ids: migratedTaskIDs, on: db)
            }
        }

        runMigrationStep("task dependencies", to: userID) { db in
            let migratedTaskDependencyData = try taskDependencyStore.migrateDependencies(from: StorageOwner.local, to: userID, on: db)
            if !migratedTaskDependencyData.taskTaskDependencyIDs.isEmpty {
                try syncStateStore.markDirty(
                    userID: userID,
                    kind: .taskTaskDependencies,
                    ids: migratedTaskDependencyData.taskTaskDependencyIDs,
                    on: db
                )
            }
            if !migratedTaskDependencyData.taskRecurringTaskDependencyIDs.isEmpty {
                try syncStateStore.markDirty(
                    userID: userID,
                    kind: .taskRecurringTaskDependencies,
                    ids: migratedTaskDependencyData.taskRecurringTaskDependencyIDs,
                    on: db
                )
            }
        }

        runMigrationStep("recurring tasks", to: userID) { db in
            let migratedRecurringTaskIDs = try recurringTaskStore.migrateRecurringTasks(from: StorageOwner.local, to: userID, on: db)
            if !migratedRecurringTaskIDs.isEmpty {
                try syncStateStore.markDirty(userID: userID, kind: .recurringTasks, ids: migratedRecurringTaskIDs, on: db)
            }
        }

        runMigrationStep("rewards", to: userID) { db in
            let migratedRewardIDs = try rewardStore.migrateRewards(from: StorageOwner.local, to: userID, on: db)
            if !migratedRewardIDs.isEmpty {
                try syncStateStore.markDirty(userID: userID, kind: .rewards, ids: migratedRewardIDs, on: db)
            }
        }

        runMigrationStep("reward dependencies", to: userID) { db in
            let migratedRewardDependencyData = try rewardDependencyStore.migrateDependencies(from: StorageOwner.local, to: userID, on: db)
            if !migratedRewardDependencyData.rewardTaskDependencyIDs.isEmpty {
                try syncStateStore.markDirty(userID: userID, kind: .rewardTaskDependencies, ids: migratedRewardDependencyData.rewardTaskDependencyIDs, on: db)
            }
            if !migratedRewardDependencyData.rewardRecurringTaskDependencyIDs.isEmpty {
                try syncStateStore.markDirty(
                    userID: userID,
                    kind: .rewardRecurringTaskDependencies,
                    ids: migratedRewardDependencyData.rewardRecurringTaskDependencyIDs,
                    on: db
                )
            }
        }

        runMigrationStep("trades", to: userID) { db in
            let migratedTradeIDs = try tradeStore.migrateTrades(from: StorageOwner.local, to: userID, on: db)
            if !migratedTradeIDs.isEmpty {
                try syncStateStore.markDirty(userID: userID, kind: .trades, ids: migratedTradeIDs, on: db)
            }
        }

        runMigrationStep("tags", to: userID) { db in
            let migratedTagData = try tagStore.migrateData(from: StorageOwner.local, to: userID, on: db)
            if !migratedTagData.tagIDs.isEmpty {
                try syncStateStore.markDirty(userID: userID, kind: .tags, ids: migratedTagData.tagIDs, on: db)
            }
            if !migratedTagData.taskTagIDs.isEmpty {
                try syncStateStore.markDirty(userID: userID, kind: .taskTags, ids: migratedTagData.taskTagIDs, on: db)
            }
            if !migratedTagData.recurringTaskTagIDs.isEmpty {
                try syncStateStore.markDirty(userID: userID, kind: .recurringTaskTags, ids: migratedTagData.recurringTaskTagIDs, on: db)
            }
            if !migratedTagData.rewardTagIDs.isEmpty {
                try syncStateStore.markDirty(userID: userID, kind: .rewardTags, ids: migratedTagData.rewardTagIDs, on: db)
            }
        }

        runMigrationStep("settings", to: userID) { db in
            let migratedSettings = try userSettingsStore.migrateSettings(from: StorageOwner.local, to: userID, on: db)
            if migratedSettings {
                try syncStateStore.markDirty(userID: userID, kind: .themePalettes, ids: [], on: db)
            }
        }

        runMigrationStep("reminders", to: userID) { db in
            try reminderStore.migrateReminders(from: StorageOwner.local, to: userID, on: db)
        }

        runMigrationStep("list preferences", to: userID) { db in
            _ = try listPreferencesStore.migratePreferences(from: StorageOwner.local, to: userID, on: db)
        }

        runMigrationStep("full sync requirement", to: userID) { db in
            try syncStateStore.forceFullSyncOnNextRun(userID: userID, on: db)
        }
    }

    private func runMigrationStep(
        _ name: String,
        to userID: String,
        _ body: (AppDatabaseHandle) throws -> Void
    ) {
        do {
            try AppDatabase.shared.transaction(at: syncStateStore.databaseURL) { db in
                try body(db)
            }
        } catch {
            // Behaviour: one corrupt or conflicting local category should not
            // block sign-in or strand every other category under the signed-out
            // owner. The failed category remains local for manual recovery or a
            // later app version that can handle that shape.
            debugPrint("Failed to migrate local \(name) into signed-in owner \(userID): \(error)")
        }
    }
}
