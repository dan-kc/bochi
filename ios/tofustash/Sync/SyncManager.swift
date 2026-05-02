import Foundation

@Observable
@MainActor
final class SyncManager {
    private let apiClient: SyncAPIClient
    private let authManager: AuthManager
    private let syncStateStore: SyncStateStore
    private let taskStore: TaskStore
    private let taskDependencyStore: TaskDependencyStore
    private let habitStore: HabitStore
    private let rewardStore: RewardStore
    private let specialOfferStore: SpecialOfferStore
    private let tradeStore: TradeStore
    private let tagStore: TagStore
    private let balanceStore: BalanceStore
    private let userSettingsStore: UserSettingsStore
    private let reminderStore: ReminderStore
    private let listPreferencesStore: ListPreferencesStore

    private var mutationObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private var backgroundPullTask: Task<Void, Never>?
    private var fullSyncResetTask: Task<Void, Never>?
    private var currentUserID: String?
    private var isSyncing = false

    private let debounceDuration: Duration
    private let backgroundPullDuration: Duration
    private let fullSyncResetDuration: Duration

    private(set) var status: SyncStatus = .idle
    private(set) var lastSyncTime: Date?
    private(set) var lastErrorMessage: String?

    private struct SyncPayload {
        let tasks: [TaskItem]
        let taskTaskDependencies: [TaskTaskDependency]
        let taskHabitDependencies: [TaskHabitDependency]
        let habits: [Habit]
        let trades: [Trade]
        let tags: [Tag]
        let taskTags: [TaskTag]
        let habitTags: [HabitTag]
        let rewards: [Reward]
        let rewardTags: [RewardTag]
        let specialOffers: [SpecialOffer]
    }

    init(
        apiClient: SyncAPIClient,
        authManager: AuthManager,
        syncStateStore: SyncStateStore,
        taskStore: TaskStore,
        taskDependencyStore: TaskDependencyStore,
        habitStore: HabitStore,
        rewardStore: RewardStore,
        specialOfferStore: SpecialOfferStore,
        tradeStore: TradeStore,
        tagStore: TagStore,
        balanceStore: BalanceStore,
        userSettingsStore: UserSettingsStore,
        reminderStore: ReminderStore,
        listPreferencesStore: ListPreferencesStore,
        debounceDuration: Duration = .seconds(6),
        backgroundPullDuration: Duration = .seconds(10),
        fullSyncResetDuration: Duration = .seconds(60 * 60 * 24)
    ) {
        self.apiClient = apiClient
        self.authManager = authManager
        self.syncStateStore = syncStateStore
        self.taskStore = taskStore
        self.taskDependencyStore = taskDependencyStore
        self.habitStore = habitStore
        self.rewardStore = rewardStore
        self.specialOfferStore = specialOfferStore
        self.tradeStore = tradeStore
        self.tagStore = tagStore
        self.balanceStore = balanceStore
        self.userSettingsStore = userSettingsStore
        self.reminderStore = reminderStore
        self.listPreferencesStore = listPreferencesStore
        self.debounceDuration = debounceDuration
        self.backgroundPullDuration = backgroundPullDuration
        self.fullSyncResetDuration = fullSyncResetDuration

        mutationObserver = SyncMutationCenter.observe { [weak self] mutation in
            Task { @MainActor [weak self] in
                self?.handleMutation(mutation)
            }
        }
    }

    var statusText: String {
        switch status {
        case .idle:
            return "Idle"
        case .syncing:
            return "Syncing"
        case .synced:
            return "Synced"
        case .error:
            return "Sync Error"
        }
    }

    var statusIconName: String {
        switch status {
        case .idle:
            return "arrow.triangle.2.circlepath"
        case .syncing:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .synced:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }

    func updateSession(userID: String?) {
        if let userID {
            applyAuthenticatedOwner(userID)
        } else {
            applySignedOutOwner()
        }
    }

    func handleAppDidBecomeActive() {
        guard currentUserID != nil else { return }
        Task { await executeBackgroundPull() }
    }

    func triggerSync() {
        debounceTask?.cancel()
        debounceTask = nil

        Task {
            await executeSync()
        }
    }

    func syncNow() async {
        debounceTask?.cancel()
        debounceTask = nil
        await executeSync()
    }

    private func applyAuthenticatedOwner(_ userID: String) {
        let previousUserID = currentUserID

        if previousUserID != userID {
            cancelLifecycleTasks()
            migrateLocalDataIfNeeded(to: userID)
        }

        currentUserID = userID
        setOwnerAcrossStores(userID)

        let syncState = syncStateStore.state(for: userID)
        lastSyncTime = syncState.lastSyncTime
        if case .error = status {
            // Keep the last error visible until the next sync attempt updates it.
        } else {
            status = .idle
        }

        startLifecycleTasks()
        triggerSync()
    }

    private func applySignedOutOwner() {
        cancelLifecycleTasks()
        currentUserID = nil
        setOwnerAcrossStores(StorageOwner.local)
        status = .idle
        lastSyncTime = nil
        lastErrorMessage = nil
    }

    private func setOwnerAcrossStores(_ ownerID: String) {
        taskStore.setCurrentOwner(ownerID)
        taskDependencyStore.setCurrentOwner(ownerID)
        habitStore.setCurrentOwner(ownerID)
        rewardStore.setCurrentOwner(ownerID)
        specialOfferStore.setCurrentOwner(ownerID)
        tradeStore.setCurrentOwner(ownerID)
        tagStore.setCurrentOwner(ownerID)
        balanceStore.setCurrentOwner(ownerID)
        userSettingsStore.setCurrentOwner(ownerID)
        reminderStore.setCurrentOwner(ownerID)
        listPreferencesStore.setCurrentOwner(ownerID)
        sanitizeListPreferencesForCurrentOwner()
    }

    private func migrateLocalDataIfNeeded(to userID: String) {
        do {
            try AppDatabase.shared.transaction(at: syncStateStore.databaseURL) { db in
                let migratedTaskIDs = try taskStore.migrateTasks(from: StorageOwner.local, to: userID, on: db)
                let migratedTaskDependencyData = try taskDependencyStore.migrateDependencies(from: StorageOwner.local, to: userID, on: db)
                let migratedHabitIDs = try habitStore.migrateHabits(from: StorageOwner.local, to: userID, on: db)
                let migratedRewardIDs = try rewardStore.migrateRewards(from: StorageOwner.local, to: userID, on: db)
                let migratedTradeIDs = try tradeStore.migrateTrades(from: StorageOwner.local, to: userID, on: db)
                let migratedTagData = try tagStore.migrateData(from: StorageOwner.local, to: userID, on: db)
                let migratedDifficulty = try userSettingsStore.migrateSettings(from: StorageOwner.local, to: userID, on: db)
                try reminderStore.migrateReminders(from: StorageOwner.local, to: userID, on: db)
                _ = try listPreferencesStore.migratePreferences(from: StorageOwner.local, to: userID, on: db)

                if !migratedTaskIDs.isEmpty {
                    try syncStateStore.markDirty(userID: userID, kind: .tasks, ids: migratedTaskIDs, on: db)
                }
                if !migratedTaskDependencyData.taskTaskDependencyIDs.isEmpty {
                    try syncStateStore.markDirty(
                        userID: userID,
                        kind: .taskTaskDependencies,
                        ids: migratedTaskDependencyData.taskTaskDependencyIDs,
                        on: db
                    )
                }
                if !migratedTaskDependencyData.taskHabitDependencyIDs.isEmpty {
                    try syncStateStore.markDirty(
                        userID: userID,
                        kind: .taskHabitDependencies,
                        ids: migratedTaskDependencyData.taskHabitDependencyIDs,
                        on: db
                    )
                }
                if !migratedHabitIDs.isEmpty {
                    try syncStateStore.markDirty(userID: userID, kind: .habits, ids: migratedHabitIDs, on: db)
                }
                if !migratedRewardIDs.isEmpty {
                    try syncStateStore.markDirty(userID: userID, kind: .rewards, ids: migratedRewardIDs, on: db)
                }
                if !migratedTradeIDs.isEmpty {
                    try syncStateStore.markDirty(userID: userID, kind: .trades, ids: migratedTradeIDs, on: db)
                }
                if !migratedTagData.tagIDs.isEmpty {
                    try syncStateStore.markDirty(userID: userID, kind: .tags, ids: migratedTagData.tagIDs, on: db)
                }
                if !migratedTagData.taskTagIDs.isEmpty {
                    try syncStateStore.markDirty(userID: userID, kind: .taskTags, ids: migratedTagData.taskTagIDs, on: db)
                }
                if !migratedTagData.habitTagIDs.isEmpty {
                    try syncStateStore.markDirty(userID: userID, kind: .habitTags, ids: migratedTagData.habitTagIDs, on: db)
                }
                if !migratedTagData.rewardTagIDs.isEmpty {
                    try syncStateStore.markDirty(userID: userID, kind: .rewardTags, ids: migratedTagData.rewardTagIDs, on: db)
                }
                if migratedDifficulty {
                    try syncStateStore.markDirty(userID: userID, kind: .generalDifficulty, ids: [], on: db)
                }
                try syncStateStore.forceFullSyncOnNextRun(userID: userID, on: db)
            }
            setOwnerAcrossStores(userID)
        } catch {
            assertionFailure("Failed to migrate local data for sync: \(error)")
        }
    }

    private func startLifecycleTasks() {
        guard backgroundPullTask == nil, let userID = currentUserID else { return }
        let backgroundPullDuration = self.backgroundPullDuration
        let fullSyncResetDuration = self.fullSyncResetDuration

        backgroundPullTask = Task { [weak self, backgroundPullDuration, userID] in
            while !Task.isCancelled {
                try? await Task.sleep(for: backgroundPullDuration)
                guard !Task.isCancelled else { return }
                await self?.runBackgroundPullIfCurrentUserMatches(userID)
            }
        }

        fullSyncResetTask = Task { [weak self, fullSyncResetDuration, userID] in
            while !Task.isCancelled {
                try? await Task.sleep(for: fullSyncResetDuration)
                guard !Task.isCancelled else { return }
                await self?.forceFullSyncIfCurrentUserMatches(userID)
            }
        }
    }

    private func cancelLifecycleTasks() {
        debounceTask?.cancel()
        debounceTask = nil
        backgroundPullTask?.cancel()
        backgroundPullTask = nil
        fullSyncResetTask?.cancel()
        fullSyncResetTask = nil
    }

    private func handleMutation(_ mutation: SyncMutation) {
        guard let currentUserID, mutation.ownerID == currentUserID else { return }
        scheduleDebouncedSync()
    }

    private func scheduleDebouncedSync() {
        debounceTask?.cancel()
        let debounceDuration = self.debounceDuration
        debounceTask = Task { [weak self, debounceDuration] in
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return }
            await self?.executeSync()
        }
    }

    private func runBackgroundPullIfCurrentUserMatches(_ userID: String) async {
        guard currentUserID == userID else { return }
        await executeBackgroundPull()
    }

    private func forceFullSyncIfCurrentUserMatches(_ userID: String) async {
        guard currentUserID == userID else { return }
        syncStateStore.forceFullSyncOnNextRun(userID: userID)
    }

    private func executeBackgroundPull() async {
        guard !isSyncing, let currentUserID, let accessToken = authManager.currentAccessTokenForSync() else {
            return
        }

        do {
            let syncState = syncStateStore.state(for: currentUserID)
            let response = try await apiClient.pullSync(cursor: syncState.lastSyncCursor, accessToken: accessToken)
            let currentSyncState = syncStateStore.state(for: currentUserID)
            try applyPullResponse(response, filteringDirtyState: currentSyncState)
        } catch {
            // Background pulls are intentionally silent so passive polling does
            // not surface noisy errors while the user is offline.
        }
    }

    private func executeSync() async {
        guard !isSyncing, let currentUserID, let accessToken = authManager.currentAccessTokenForSync() else {
            return
        }

        isSyncing = true
        status = .syncing
        lastErrorMessage = nil

        if syncStateStore.shouldPerformFullSync(userID: currentUserID) {
            syncStateStore.forceFullSyncOnNextRun(userID: currentUserID)
        }

        let syncState = syncStateStore.state(for: currentUserID)
        let isFullSync = syncState.lastSyncCursor == nil

        do {
            let pullResponse = try await apiClient.pullSync(cursor: syncState.lastSyncCursor, accessToken: accessToken)
            let syncStateAfterPull = syncStateStore.state(for: currentUserID)
            let dirtySnapshot = makeDirtyIDSnapshot(from: syncStateAfterPull)

            let dirtyTasks = taskStore.getDirtyTasks(ids: Set(dirtySnapshot.tasks.keys))
            let dirtyTaskTaskDependencies = taskDependencyStore.getDirtyTaskTaskDependencies(ids: Set(dirtySnapshot.taskTaskDependencies.keys))
            let dirtyTaskHabitDependencies = taskDependencyStore.getDirtyTaskHabitDependencies(ids: Set(dirtySnapshot.taskHabitDependencies.keys))
            let dirtyHabits = habitStore.getDirtyHabits(ids: Set(dirtySnapshot.habits.keys))
            let dirtyTrades = tradeStore.getDirtyTrades(ids: Set(dirtySnapshot.trades.keys))
            let dirtyTags = tagStore.getDirtyTags(ids: Set(dirtySnapshot.tags.keys))
            let dirtyTaskTags = tagStore.getDirtyTaskTags(ids: Set(dirtySnapshot.taskTags.keys))
            let dirtyHabitTags = tagStore.getDirtyHabitTags(ids: Set(dirtySnapshot.habitTags.keys))
            let dirtyRewards = rewardStore.getDirtyRewards(ids: Set(dirtySnapshot.rewards.keys))
            let dirtyRewardTags = tagStore.getDirtyRewardTags(ids: Set(dirtySnapshot.rewardTags.keys))
            let generalDifficultyDirty = syncStateAfterPull.dirty.generalDifficulty

            if isFullSync {
                try replaceCurrentOwnerStateFromFullPull(
                    pullResponse: pullResponse,
                    dirtyTasks: dirtyTasks,
                    dirtyTaskTaskDependencies: dirtyTaskTaskDependencies,
                    dirtyTaskHabitDependencies: dirtyTaskHabitDependencies,
                    dirtyHabits: dirtyHabits,
                    dirtyTrades: dirtyTrades,
                    dirtyTags: dirtyTags,
                    dirtyTaskTags: dirtyTaskTags,
                    dirtyHabitTags: dirtyHabitTags,
                    dirtyRewards: dirtyRewards,
                    dirtyRewardTags: dirtyRewardTags,
                    generalDifficultyDirty: generalDifficultyDirty
                )
            } else {
                try applyPullResponse(pullResponse, filteringDirtyState: syncStateAfterPull)
            }

            var checkpointResponse = pullResponse
            if !dirtyTasks.isEmpty
                || !dirtyTaskTaskDependencies.isEmpty
                || !dirtyTaskHabitDependencies.isEmpty
                || !dirtyHabits.isEmpty
                || !dirtyTrades.isEmpty
                || !dirtyTags.isEmpty
                || !dirtyTaskTags.isEmpty
                || !dirtyHabitTags.isEmpty
                || !dirtyRewards.isEmpty
                || !dirtyRewardTags.isEmpty
                || generalDifficultyDirty
            {
                let taskRecords: [SyncTaskRecord]? = dirtyTasks.isEmpty ? nil : dirtyTasks.map(SyncTaskRecord.from)
                let taskTaskDependencyRecords: [SyncTaskTaskDependencyRecord]? =
                    dirtyTaskTaskDependencies.isEmpty ? nil : dirtyTaskTaskDependencies.map(SyncTaskTaskDependencyRecord.from)
                let taskHabitDependencyRecords: [SyncTaskHabitDependencyRecord]? =
                    dirtyTaskHabitDependencies.isEmpty ? nil : dirtyTaskHabitDependencies.map(SyncTaskHabitDependencyRecord.from)
                let habitRecords: [SyncHabitRecord]? = dirtyHabits.isEmpty ? nil : dirtyHabits.map(SyncHabitRecord.from)
                let tradeRecords: [SyncTradeRecord]? = dirtyTrades.isEmpty ? nil : dirtyTrades.map(SyncTradeRecord.from)
                let tagRecords: [SyncTagRecord]? = dirtyTags.isEmpty ? nil : dirtyTags.map(SyncTagRecord.from)
                let taskTagRecords: [SyncTaskTagRecord]? = dirtyTaskTags.isEmpty ? nil : dirtyTaskTags.map(SyncTaskTagRecord.from)
                let habitTagRecords: [SyncHabitTagRecord]? = dirtyHabitTags.isEmpty ? nil : dirtyHabitTags.map(SyncHabitTagRecord.from)
                let rewardRecords: [SyncRewardRecord]? = dirtyRewards.isEmpty ? nil : dirtyRewards.map(SyncRewardRecord.from)
                let rewardTagRecords: [SyncRewardTagRecord]? = dirtyRewardTags.isEmpty ? nil : dirtyRewardTags.map(SyncRewardTagRecord.from)

                let pushRequest = SyncPushRequest(
                    tasks: taskRecords,
                    habits: habitRecords,
                    trades: tradeRecords,
                    tags: tagRecords,
                    taskTags: taskTagRecords,
                    taskTaskDependencies: taskTaskDependencyRecords,
                    taskHabitDependencies: taskHabitDependencyRecords,
                    habitTags: habitTagRecords,
                    rewards: rewardRecords,
                    rewardTags: rewardTagRecords,
                    generalDifficulty: generalDifficultyDirty ? userSettingsStore.generalDifficulty : nil
                )

                let response = try await apiClient.pushSync(pushRequest, accessToken: accessToken)
                try applyPushResponse(response)
                checkpointResponse = response
            }

            let serverTime = AppDateCoding.parseBackendTimestamp(checkpointResponse.serverTime) ?? Date()
            let completedFullSync = isFullSync
            try AppDatabase.shared.transaction(at: syncStateStore.databaseURL) { db in
                try self.syncStateStore.completeSync(
                    userID: currentUserID,
                    snapshot: syncStateAfterPull,
                    serverCursor: checkpointResponse.serverCursor,
                    serverTime: serverTime,
                    completedFullSync: completedFullSync,
                    on: db
                )

                let remainingDirty = try self.syncStateStore.state(for: currentUserID, on: db)
                try self.taskStore.purgeDeletedTasks(excluding: Set(remainingDirty.dirty.tasks.map(\.id)), on: db)
                try self.taskDependencyStore.purgeDeleted(
                    taskTaskDependencyIDs: Set(remainingDirty.dirty.taskTaskDependencies.map(\.id)),
                    taskHabitDependencyIDs: Set(remainingDirty.dirty.taskHabitDependencies.map(\.id)),
                    on: db
                )
                try self.habitStore.purgeDeletedHabits(excluding: Set(remainingDirty.dirty.habits.map(\.id)), on: db)
                try self.tradeStore.purgeDeletedTrades(excluding: Set(remainingDirty.dirty.trades.map(\.id)), on: db)
                try self.tagStore.purgeDeleted(
                    excludingTagIDs: Set(remainingDirty.dirty.tags.map(\.id)),
                    taskTagIDs: Set(remainingDirty.dirty.taskTags.map(\.id)),
                    habitTagIDs: Set(remainingDirty.dirty.habitTags.map(\.id)),
                    rewardTagIDs: Set(remainingDirty.dirty.rewardTags.map(\.id)),
                    on: db
                )
                try self.rewardStore.purgeDeletedRewards(excluding: Set(remainingDirty.dirty.rewards.map(\.id)), on: db)
                try self.specialOfferStore.purgeDeletedOffers(on: db)
            }
            lastSyncTime = serverTime
            setOwnerAcrossStores(currentUserID)
            reminderStore.reconcileNotifications()

            status = .synced
        } catch {
            let message = (error as? ApiError)?.userFacingMessage
                ?? (error as? LocalizedError)?.errorDescription
                ?? "Sync failed."
            lastErrorMessage = message
            status = .error(message)
        }

        isSyncing = false
    }

    private func replaceCurrentOwnerStateFromFullPull(
        pullResponse: SyncResponse,
        dirtyTasks: [TaskItem],
        dirtyTaskTaskDependencies: [TaskTaskDependency],
        dirtyTaskHabitDependencies: [TaskHabitDependency],
        dirtyHabits: [Habit],
        dirtyTrades: [Trade],
        dirtyTags: [Tag],
        dirtyTaskTags: [TaskTag],
        dirtyHabitTags: [HabitTag],
        dirtyRewards: [Reward],
        dirtyRewardTags: [RewardTag],
        generalDifficultyDirty: Bool
    ) throws {
        let payload = makeSyncPayload(from: pullResponse)
        let authoritativePayload = SyncPayload(
            tasks: OwnerScopedRecordSupport.mergeRecords(local: payload.tasks, remote: dirtyTasks),
            taskTaskDependencies: OwnerScopedRecordSupport.mergeRecords(
                local: payload.taskTaskDependencies,
                remote: dirtyTaskTaskDependencies
            ),
            taskHabitDependencies: OwnerScopedRecordSupport.mergeRecords(
                local: payload.taskHabitDependencies,
                remote: dirtyTaskHabitDependencies
            ),
            habits: OwnerScopedRecordSupport.mergeRecords(local: payload.habits, remote: dirtyHabits),
            trades: OwnerScopedRecordSupport.mergeRecords(local: payload.trades, remote: dirtyTrades),
            tags: OwnerScopedRecordSupport.mergeRecords(local: payload.tags, remote: dirtyTags),
            taskTags: OwnerScopedRecordSupport.mergeRecords(local: payload.taskTags, remote: dirtyTaskTags),
            habitTags: OwnerScopedRecordSupport.mergeRecords(local: payload.habitTags, remote: dirtyHabitTags),
            rewards: OwnerScopedRecordSupport.mergeRecords(local: payload.rewards, remote: dirtyRewards),
            rewardTags: OwnerScopedRecordSupport.mergeRecords(local: payload.rewardTags, remote: dirtyRewardTags),
            specialOffers: payload.specialOffers
        )

        try persistSyncPayload(authoritativePayload)
        if !dirtyTrades.isEmpty {
            balanceStore.refresh()
        } else {
            try balanceStore.persistBalance(Int(pullResponse.balance.tofuBalance.rounded()))
        }
        if !generalDifficultyDirty {
            try userSettingsStore.persistGeneralDifficulty(pullResponse.generalDifficulty)
        }
    }

    private func applyPullResponse(_ response: SyncResponse, filteringDirtyState dirtyState: SyncStateStore.UserSyncState?) throws {
        let dirtyIDs: DirtyIDSnapshot
        if let dirtyState {
            dirtyIDs = makeDirtyIDSnapshot(from: dirtyState)
        } else {
            dirtyIDs = DirtyIDSnapshot()
        }

        let payload = makeSyncPayload(from: response, excluding: dirtyIDs)
        try persistSyncPayload(mergeCurrentState(with: payload))

        if dirtyIDs.trades.isEmpty {
            try balanceStore.persistBalance(Int(response.balance.tofuBalance.rounded()))
        } else {
            balanceStore.refresh()
        }

        if !(dirtyState?.dirty.generalDifficulty ?? false) {
            try userSettingsStore.persistGeneralDifficulty(response.generalDifficulty)
        }

        if
            let serverTime = AppDateCoding.parseBackendTimestamp(response.serverTime),
            let currentUserID
        {
            try AppDatabase.shared.transaction(at: syncStateStore.databaseURL) { db in
                try self.syncStateStore.updateCheckpoint(
                    userID: currentUserID,
                    serverCursor: response.serverCursor,
                    serverTime: serverTime,
                    completedFullSync: false,
                    on: db
                )
            }
            lastSyncTime = serverTime
        }
    }

    private func applyPushResponse(_ response: SyncResponse) throws {
        try persistSyncPayload(mergeCurrentState(with: makeSyncPayload(from: response)))

        try balanceStore.persistBalance(Int(response.balance.tofuBalance.rounded()))
        try userSettingsStore.persistGeneralDifficulty(response.generalDifficulty)
    }

    private func makeSyncPayload(
        from response: SyncResponse,
        excluding dirtyIDs: DirtyIDSnapshot? = nil
    ) -> SyncPayload {
        SyncPayload(
            tasks: response.tasks.compactMap { record in
                guard let model = record.toModel() else { return nil }
                guard dirtyIDs?.tasks[model.id] == nil else { return nil }
                return model
            },
            taskTaskDependencies: response.taskTaskDependencies.compactMap { record in
                guard let model = record.toModel() else { return nil }
                guard dirtyIDs?.taskTaskDependencies[model.id] == nil else { return nil }
                return model
            },
            taskHabitDependencies: response.taskHabitDependencies.compactMap { record in
                guard let model = record.toModel() else { return nil }
                guard dirtyIDs?.taskHabitDependencies[model.id] == nil else { return nil }
                return model
            },
            habits: response.habits.compactMap { record in
                guard let model = record.toModel() else { return nil }
                guard dirtyIDs?.habits[model.id] == nil else { return nil }
                return model
            },
            trades: response.trades.compactMap { record in
                guard let model = record.toModel() else { return nil }
                guard dirtyIDs?.trades[model.id] == nil else { return nil }
                return model
            },
            tags: response.tags.compactMap { record in
                guard let model = record.toModel() else { return nil }
                guard dirtyIDs?.tags[model.id] == nil else { return nil }
                return model
            },
            taskTags: response.taskTags.compactMap { record in
                guard let model = record.toModel() else { return nil }
                guard dirtyIDs?.taskTags[model.id] == nil else { return nil }
                return model
            },
            habitTags: response.habitTags.compactMap { record in
                guard let model = record.toModel() else { return nil }
                guard dirtyIDs?.habitTags[model.id] == nil else { return nil }
                return model
            },
            rewards: response.rewards.compactMap { record in
                guard let model = record.toModel() else { return nil }
                guard dirtyIDs?.rewards[model.id] == nil else { return nil }
                return model
            },
            rewardTags: response.rewardTags.compactMap { record in
                guard let model = record.toModel() else { return nil }
                guard dirtyIDs?.rewardTags[model.id] == nil else { return nil }
                return model
            },
            specialOffers: response.specialOffers.compactMap { $0.toModel() }
        )
    }

    private func mergeCurrentState(with incoming: SyncPayload) -> SyncPayload {
        SyncPayload(
            tasks: incoming.tasks.isEmpty
                ? taskStore.tasks
                : OwnerScopedRecordSupport.mergeRecords(local: taskStore.tasks, remote: incoming.tasks),
            taskTaskDependencies: incoming.taskTaskDependencies.isEmpty
                ? taskDependencyStore.taskTaskDependencies
                : OwnerScopedRecordSupport.mergeRecords(
                    local: taskDependencyStore.taskTaskDependencies,
                    remote: incoming.taskTaskDependencies
                ),
            taskHabitDependencies: incoming.taskHabitDependencies.isEmpty
                ? taskDependencyStore.taskHabitDependencies
                : OwnerScopedRecordSupport.mergeRecords(
                    local: taskDependencyStore.taskHabitDependencies,
                    remote: incoming.taskHabitDependencies
                ),
            habits: incoming.habits.isEmpty
                ? habitStore.habits
                : OwnerScopedRecordSupport.mergeRecords(local: habitStore.habits, remote: incoming.habits),
            trades: incoming.trades.isEmpty
                ? tradeStore.trades
                : OwnerScopedRecordSupport.mergeRecords(local: tradeStore.trades, remote: incoming.trades),
            tags: incoming.tags.isEmpty
                ? tagStore.tags
                : OwnerScopedRecordSupport.mergeRecords(local: tagStore.tags, remote: incoming.tags),
            taskTags: incoming.taskTags.isEmpty
                ? tagStore.taskTags
                : OwnerScopedRecordSupport.mergeRecords(local: tagStore.taskTags, remote: incoming.taskTags),
            habitTags: incoming.habitTags.isEmpty
                ? tagStore.habitTags
                : OwnerScopedRecordSupport.mergeRecords(local: tagStore.habitTags, remote: incoming.habitTags),
            rewards: incoming.rewards.isEmpty
                ? rewardStore.rewards
                : OwnerScopedRecordSupport.mergeRecords(local: rewardStore.rewards, remote: incoming.rewards),
            rewardTags: incoming.rewardTags.isEmpty
                ? tagStore.rewardTags
                : OwnerScopedRecordSupport.mergeRecords(local: tagStore.rewardTags, remote: incoming.rewardTags),
            specialOffers: incoming.specialOffers.isEmpty
                ? specialOfferStore.offers
                : OwnerScopedRecordSupport.mergeRecords(local: specialOfferStore.offers, remote: incoming.specialOffers)
        )
    }

    private func persistSyncPayload(_ payload: SyncPayload) throws {
        try taskStore.persistReplacedTasks(payload.tasks)
        try taskDependencyStore.persistReplacedAll(
            taskTaskDependencies: payload.taskTaskDependencies,
            taskHabitDependencies: payload.taskHabitDependencies
        )
        try habitStore.persistReplacedHabits(payload.habits)
        try tradeStore.persistReplacedTrades(payload.trades)
        try tagStore.persistReplacedAll(
            tags: payload.tags,
            taskTags: payload.taskTags,
            habitTags: payload.habitTags,
            rewardTags: payload.rewardTags
        )
        try rewardStore.persistReplacedRewards(payload.rewards)
        try specialOfferStore.persistReplacedOffers(payload.specialOffers)
        sanitizeListPreferencesForCurrentOwner()
        reminderStore.reconcileNotifications()
    }

    private struct DirtyIDSnapshot {
        var tasks: [RecordID: Int64] = [:]
        var habits: [RecordID: Int64] = [:]
        var trades: [RecordID: Int64] = [:]
        var tags: [RecordID: Int64] = [:]
        var taskTags: [RecordID: Int64] = [:]
        var taskTaskDependencies: [RecordID: Int64] = [:]
        var taskHabitDependencies: [RecordID: Int64] = [:]
        var habitTags: [RecordID: Int64] = [:]
        var rewards: [RecordID: Int64] = [:]
        var rewardTags: [RecordID: Int64] = [:]
    }

    private func makeDirtyIDSnapshot(from state: SyncStateStore.UserSyncState) -> DirtyIDSnapshot {
        DirtyIDSnapshot(
            tasks: Dictionary(uniqueKeysWithValues: state.dirty.tasks.map { ($0.id, $0.generation) }),
            habits: Dictionary(uniqueKeysWithValues: state.dirty.habits.map { ($0.id, $0.generation) }),
            trades: Dictionary(uniqueKeysWithValues: state.dirty.trades.map { ($0.id, $0.generation) }),
            tags: Dictionary(uniqueKeysWithValues: state.dirty.tags.map { ($0.id, $0.generation) }),
            taskTags: Dictionary(uniqueKeysWithValues: state.dirty.taskTags.map { ($0.id, $0.generation) }),
            taskTaskDependencies: Dictionary(uniqueKeysWithValues: state.dirty.taskTaskDependencies.map { ($0.id, $0.generation) }),
            taskHabitDependencies: Dictionary(uniqueKeysWithValues: state.dirty.taskHabitDependencies.map { ($0.id, $0.generation) }),
            habitTags: Dictionary(uniqueKeysWithValues: state.dirty.habitTags.map { ($0.id, $0.generation) }),
            rewards: Dictionary(uniqueKeysWithValues: state.dirty.rewards.map { ($0.id, $0.generation) }),
            rewardTags: Dictionary(uniqueKeysWithValues: state.dirty.rewardTags.map { ($0.id, $0.generation) })
        )
    }
    private func sanitizeListPreferencesForCurrentOwner() {
        // User behaviour: when account switching, sync, or local migration changes
        // which tags exist for the current owner, any saved filter chips for
        // deleted tags should disappear instead of silently hiding all rows.
        listPreferencesStore.sanitizeSelectedTags(
            validTaskTagIDs: tagStore.activeTagIDs,
            validHabitTagIDs: tagStore.activeTagIDs,
            validRewardTagIDs: tagStore.activeTagIDs
        )
    }
}
