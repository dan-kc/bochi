import Foundation

@Observable
@MainActor
final class SyncManager {
    private let apiClient: SyncAPIClient
    private let authManager: AuthManager
    private let syncStateStore: SyncStateStore
    private let habitStore: HabitStore
    private let rewardStore: RewardStore
    private let tradeStore: TradeStore
    private let tagStore: TagStore
    private let balanceStore: BalanceStore
    private let userSettingsStore: UserSettingsStore
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

    init(
        apiClient: SyncAPIClient,
        authManager: AuthManager,
        syncStateStore: SyncStateStore,
        habitStore: HabitStore,
        rewardStore: RewardStore,
        tradeStore: TradeStore,
        tagStore: TagStore,
        balanceStore: BalanceStore,
        userSettingsStore: UserSettingsStore,
        listPreferencesStore: ListPreferencesStore,
        debounceDuration: Duration = .seconds(2),
        backgroundPullDuration: Duration = .seconds(5),
        fullSyncResetDuration: Duration = .seconds(60 * 60 * 24)
    ) {
        self.apiClient = apiClient
        self.authManager = authManager
        self.syncStateStore = syncStateStore
        self.habitStore = habitStore
        self.rewardStore = rewardStore
        self.tradeStore = tradeStore
        self.tagStore = tagStore
        self.balanceStore = balanceStore
        self.userSettingsStore = userSettingsStore
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
        habitStore.setCurrentOwner(ownerID)
        rewardStore.setCurrentOwner(ownerID)
        tradeStore.setCurrentOwner(ownerID)
        tagStore.setCurrentOwner(ownerID)
        balanceStore.setCurrentOwner(ownerID)
        userSettingsStore.setCurrentOwner(ownerID)
        listPreferencesStore.setCurrentOwner(ownerID)
        sanitizeListPreferencesForCurrentOwner()
    }

    private func migrateLocalDataIfNeeded(to userID: String) {
        do {
            try AppDatabase.shared.transaction(at: syncStateStore.databaseURL) { db in
                let migratedHabitIDs = try habitStore.migrateHabits(from: StorageOwner.local, to: userID, on: db)
                let migratedRewardIDs = try rewardStore.migrateRewards(from: StorageOwner.local, to: userID, on: db)
                let migratedTradeIDs = try tradeStore.migrateTrades(from: StorageOwner.local, to: userID, on: db)
                let migratedTagData = try tagStore.migrateData(from: StorageOwner.local, to: userID, on: db)
                let migratedDifficulty = try userSettingsStore.migrateSettings(from: StorageOwner.local, to: userID, on: db)
                _ = try listPreferencesStore.migratePreferences(from: StorageOwner.local, to: userID, on: db)

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

        let syncState = syncStateStore.state(for: currentUserID)

        do {
            let response = try await apiClient.pullSync(cursor: syncState.lastSyncCursor, accessToken: accessToken)
            applyPullResponse(response, filteringDirtyState: syncState)
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
        let dirtySnapshot = makeDirtyIDSnapshot(from: syncState)

        let dirtyHabits = habitStore.getDirtyHabits(ids: Set(dirtySnapshot.habits.keys))
        let dirtyTrades = tradeStore.getDirtyTrades(ids: Set(dirtySnapshot.trades.keys))
        let dirtyTags = tagStore.getDirtyTags(ids: Set(dirtySnapshot.tags.keys))
        let dirtyHabitTags = tagStore.getDirtyHabitTags(ids: Set(dirtySnapshot.habitTags.keys))
        let dirtyRewards = rewardStore.getDirtyRewards(ids: Set(dirtySnapshot.rewards.keys))
        let dirtyRewardTags = tagStore.getDirtyRewardTags(ids: Set(dirtySnapshot.rewardTags.keys))
        let generalDifficultyDirty = syncState.dirty.generalDifficulty
        let isFullSync = syncState.lastSyncCursor == nil

        do {
            let pullResponse = try await apiClient.pullSync(cursor: syncState.lastSyncCursor, accessToken: accessToken)
            if isFullSync {
                try replaceCurrentOwnerStateFromFullPull(
                    pullResponse: pullResponse,
                    dirtyHabits: dirtyHabits,
                    dirtyTrades: dirtyTrades,
                    dirtyTags: dirtyTags,
                    dirtyHabitTags: dirtyHabitTags,
                    dirtyRewards: dirtyRewards,
                    dirtyRewardTags: dirtyRewardTags,
                    generalDifficultyDirty: generalDifficultyDirty
                )
            } else {
                try applyPullResponse(pullResponse, filteringDirtyState: syncState)
            }

            if !dirtyHabits.isEmpty
                || !dirtyTrades.isEmpty
                || !dirtyTags.isEmpty
                || !dirtyHabitTags.isEmpty
                || !dirtyRewards.isEmpty
                || !dirtyRewardTags.isEmpty
                || generalDifficultyDirty
            {
                let habitRecords: [SyncHabitRecord]? = dirtyHabits.isEmpty ? nil : dirtyHabits.map(SyncHabitRecord.from)
                let tradeRecords: [SyncTradeRecord]? = dirtyTrades.isEmpty ? nil : dirtyTrades.map(SyncTradeRecord.from)
                let tagRecords: [SyncTagRecord]? = dirtyTags.isEmpty ? nil : dirtyTags.map(SyncTagRecord.from)
                let habitTagRecords: [SyncHabitTagRecord]? = dirtyHabitTags.isEmpty ? nil : dirtyHabitTags.map(SyncHabitTagRecord.from)
                let rewardRecords: [SyncRewardRecord]? = dirtyRewards.isEmpty ? nil : dirtyRewards.map(SyncRewardRecord.from)
                let rewardTagRecords: [SyncRewardTagRecord]? = dirtyRewardTags.isEmpty ? nil : dirtyRewardTags.map(SyncRewardTagRecord.from)

                let pushRequest = SyncPushRequest(
                    habits: habitRecords,
                    trades: tradeRecords,
                    tags: tagRecords,
                    habitTags: habitTagRecords,
                    rewards: rewardRecords,
                    rewardTags: rewardTagRecords,
                    generalDifficulty: generalDifficultyDirty ? userSettingsStore.generalDifficulty : nil
                )

                let response = try await apiClient.pushSync(pushRequest, accessToken: accessToken)
                try applyPushResponse(response)
            }

            let serverTime = AppDateCoding.parseBackendTimestamp(pullResponse.serverTime) ?? Date()
            let completedFullSync = isFullSync
            try AppDatabase.shared.transaction(at: syncStateStore.databaseURL) { db in
                try self.syncStateStore.completeSync(
                    userID: currentUserID,
                    snapshot: syncState,
                    serverCursor: pullResponse.serverCursor,
                    serverTime: serverTime,
                    completedFullSync: completedFullSync,
                    on: db
                )

                let remainingDirty = try self.syncStateStore.state(for: currentUserID, on: db)
                try self.habitStore.purgeDeletedHabits(excluding: Set(remainingDirty.dirty.habits.map(\.id)), on: db)
                try self.tradeStore.purgeDeletedTrades(excluding: Set(remainingDirty.dirty.trades.map(\.id)), on: db)
                try self.tagStore.purgeDeleted(
                    excludingTagIDs: Set(remainingDirty.dirty.tags.map(\.id)),
                    habitTagIDs: Set(remainingDirty.dirty.habitTags.map(\.id)),
                    rewardTagIDs: Set(remainingDirty.dirty.rewardTags.map(\.id)),
                    on: db
                )
                try self.rewardStore.purgeDeletedRewards(excluding: Set(remainingDirty.dirty.rewards.map(\.id)), on: db)
            }
            lastSyncTime = serverTime
            habitStore.setCurrentOwner(currentUserID)
            tradeStore.setCurrentOwner(currentUserID)
            tagStore.setCurrentOwner(currentUserID)
            rewardStore.setCurrentOwner(currentUserID)
            balanceStore.setCurrentOwner(currentUserID)
            userSettingsStore.setCurrentOwner(currentUserID)
            listPreferencesStore.setCurrentOwner(currentUserID)

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
        dirtyHabits: [Habit],
        dirtyTrades: [Trade],
        dirtyTags: [Tag],
        dirtyHabitTags: [HabitTag],
        dirtyRewards: [Reward],
        dirtyRewardTags: [RewardTag],
        generalDifficultyDirty: Bool
    ) throws {
        let authoritativeHabits = OwnerScopedRecordSupport.mergeRecords(
            local: pullResponse.habits.compactMap { $0.toModel() },
            remote: dirtyHabits
        )
        let authoritativeTrades = OwnerScopedRecordSupport.mergeRecords(
            local: pullResponse.trades.compactMap { $0.toModel() },
            remote: dirtyTrades
        )
        let authoritativeTags = OwnerScopedRecordSupport.mergeRecords(
            local: pullResponse.tags.compactMap { $0.toModel() },
            remote: dirtyTags
        )
        let authoritativeHabitTags = OwnerScopedRecordSupport.mergeRecords(
            local: pullResponse.habitTags.compactMap { $0.toModel() },
            remote: dirtyHabitTags
        )
        let authoritativeRewards = OwnerScopedRecordSupport.mergeRecords(
            local: pullResponse.rewards.compactMap { $0.toModel() },
            remote: dirtyRewards
        )
        let authoritativeRewardTags = OwnerScopedRecordSupport.mergeRecords(
            local: pullResponse.rewardTags.compactMap { $0.toModel() },
            remote: dirtyRewardTags
        )

        try habitStore.persistReplacedHabits(authoritativeHabits)
        try tradeStore.persistReplacedTrades(authoritativeTrades)
        try tagStore.persistReplacedAll(
            tags: authoritativeTags,
            habitTags: authoritativeHabitTags,
            rewardTags: authoritativeRewardTags
        )
        try rewardStore.persistReplacedRewards(authoritativeRewards)
        if !dirtyTrades.isEmpty {
            balanceStore.refresh()
        } else {
            try balanceStore.persistBalance(Int(pullResponse.balance.tofuBalance.rounded()))
        }
        if !generalDifficultyDirty {
            try userSettingsStore.persistGeneralDifficulty(pullResponse.generalDifficulty)
        }
        sanitizeListPreferencesForCurrentOwner()
    }

    private func applyPullResponse(_ response: SyncResponse, filteringDirtyState dirtyState: SyncStateStore.UserSyncState?) throws {
        let dirtyIDs: DirtyIDSnapshot
        if let dirtyState {
            dirtyIDs = makeDirtyIDSnapshot(from: dirtyState)
        } else {
            dirtyIDs = DirtyIDSnapshot()
        }

        let habits: [Habit] = response.habits.compactMap { record in
            let model = record.toModel()
            guard let model else { return nil }
            guard dirtyIDs.habits[model.id] == nil else { return nil }
            return model
        }

        let trades: [Trade] = response.trades.compactMap { record in
            let model = record.toModel()
            guard let model else { return nil }
            guard dirtyIDs.trades[model.id] == nil else { return nil }
            return model
        }

        let tags: [Tag] = response.tags.compactMap { record in
            let model = record.toModel()
            guard let model else { return nil }
            guard dirtyIDs.tags[model.id] == nil else { return nil }
            return model
        }

        let habitTags: [HabitTag] = response.habitTags.compactMap { record in
            let model = record.toModel()
            guard let model else { return nil }
            guard dirtyIDs.habitTags[model.id] == nil else { return nil }
            return model
        }

        let rewards: [Reward] = response.rewards.compactMap { record in
            let model = record.toModel()
            guard let model else { return nil }
            guard dirtyIDs.rewards[model.id] == nil else { return nil }
            return model
        }

        let rewardTags: [RewardTag] = response.rewardTags.compactMap { record in
            let model = record.toModel()
            guard let model else { return nil }
            guard dirtyIDs.rewardTags[model.id] == nil else { return nil }
            return model
        }

        let mergedHabits = habits.isEmpty ? habitStore.habits : OwnerScopedRecordSupport.mergeRecords(local: habitStore.habits, remote: habits)
        let mergedTrades = trades.isEmpty ? tradeStore.trades : OwnerScopedRecordSupport.mergeRecords(local: tradeStore.trades, remote: trades)
        let mergedTags = tags.isEmpty ? tagStore.tags : OwnerScopedRecordSupport.mergeRecords(local: tagStore.tags, remote: tags)
        let mergedHabitTags = habitTags.isEmpty ? tagStore.habitTags : OwnerScopedRecordSupport.mergeRecords(local: tagStore.habitTags, remote: habitTags)
        let mergedRewards = rewards.isEmpty ? rewardStore.rewards : OwnerScopedRecordSupport.mergeRecords(local: rewardStore.rewards, remote: rewards)
        let mergedRewardTags = rewardTags.isEmpty ? tagStore.rewardTags : OwnerScopedRecordSupport.mergeRecords(local: tagStore.rewardTags, remote: rewardTags)

        try habitStore.persistReplacedHabits(mergedHabits)
        try tradeStore.persistReplacedTrades(mergedTrades)
        try tagStore.persistReplacedAll(tags: mergedTags, habitTags: mergedHabitTags, rewardTags: mergedRewardTags)
        try rewardStore.persistReplacedRewards(mergedRewards)
        sanitizeListPreferencesForCurrentOwner()

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
        let habits: [Habit] = response.habits.compactMap { $0.toModel() }
        let trades: [Trade] = response.trades.compactMap { $0.toModel() }
        let tags: [Tag] = response.tags.compactMap { $0.toModel() }
        let habitTags: [HabitTag] = response.habitTags.compactMap { $0.toModel() }
        let rewards: [Reward] = response.rewards.compactMap { $0.toModel() }
        let rewardTags: [RewardTag] = response.rewardTags.compactMap { $0.toModel() }

        let mergedHabits = habits.isEmpty ? habitStore.habits : OwnerScopedRecordSupport.mergeRecords(local: habitStore.habits, remote: habits)
        let mergedTrades = trades.isEmpty ? tradeStore.trades : OwnerScopedRecordSupport.mergeRecords(local: tradeStore.trades, remote: trades)
        let mergedTags = tags.isEmpty ? tagStore.tags : OwnerScopedRecordSupport.mergeRecords(local: tagStore.tags, remote: tags)
        let mergedHabitTags = habitTags.isEmpty ? tagStore.habitTags : OwnerScopedRecordSupport.mergeRecords(local: tagStore.habitTags, remote: habitTags)
        let mergedRewards = rewards.isEmpty ? rewardStore.rewards : OwnerScopedRecordSupport.mergeRecords(local: rewardStore.rewards, remote: rewards)
        let mergedRewardTags = rewardTags.isEmpty ? tagStore.rewardTags : OwnerScopedRecordSupport.mergeRecords(local: tagStore.rewardTags, remote: rewardTags)

        try habitStore.persistReplacedHabits(mergedHabits)
        try tradeStore.persistReplacedTrades(mergedTrades)
        try tagStore.persistReplacedAll(tags: mergedTags, habitTags: mergedHabitTags, rewardTags: mergedRewardTags)
        try rewardStore.persistReplacedRewards(mergedRewards)
        sanitizeListPreferencesForCurrentOwner()

        try balanceStore.persistBalance(Int(response.balance.tofuBalance.rounded()))
        try userSettingsStore.persistGeneralDifficulty(response.generalDifficulty)
    }

    private func sanitizeListPreferencesForCurrentOwner() {
        // User behaviour: when account switching, sync, or local migration changes
        // which tags exist for the current owner, any saved filter chips for
        // deleted tags should disappear instead of silently hiding all rows.
        listPreferencesStore.sanitizeSelectedTags(
            validHabitTagIDs: tagStore.activeTagIDs,
            validRewardTagIDs: tagStore.activeTagIDs
        )
    }

    private struct DirtyIDSnapshot {
        var habits: [RecordID: Int64] = [:]
        var trades: [RecordID: Int64] = [:]
        var tags: [RecordID: Int64] = [:]
        var habitTags: [RecordID: Int64] = [:]
        var rewards: [RecordID: Int64] = [:]
        var rewardTags: [RecordID: Int64] = [:]
    }

    private func makeDirtyIDSnapshot(from state: SyncStateStore.UserSyncState) -> DirtyIDSnapshot {
        DirtyIDSnapshot(
            habits: Dictionary(uniqueKeysWithValues: state.dirty.habits.map { ($0.id, $0.generation) }),
            trades: Dictionary(uniqueKeysWithValues: state.dirty.trades.map { ($0.id, $0.generation) }),
            tags: Dictionary(uniqueKeysWithValues: state.dirty.tags.map { ($0.id, $0.generation) }),
            habitTags: Dictionary(uniqueKeysWithValues: state.dirty.habitTags.map { ($0.id, $0.generation) }),
            rewards: Dictionary(uniqueKeysWithValues: state.dirty.rewards.map { ($0.id, $0.generation) }),
            rewardTags: Dictionary(uniqueKeysWithValues: state.dirty.rewardTags.map { ($0.id, $0.generation) })
        )
    }
}
