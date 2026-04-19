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
            syncStateStore.forceFullSyncOnNextRun(userID: userID)
        }

        currentUserID = userID
        setOwnerAcrossStores(userID)

        let syncState = syncStateStore.state(for: userID)
        lastSyncTime = syncState.lastSync
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
    }

    private func migrateLocalDataIfNeeded(to userID: String) {
        let migratedHabitIDs = habitStore.migrateHabits(from: StorageOwner.local, to: userID)
        let migratedRewardIDs = rewardStore.migrateRewards(from: StorageOwner.local, to: userID)
        let migratedTradeIDs = tradeStore.migrateTrades(from: StorageOwner.local, to: userID)
        let migratedTagData = tagStore.migrateData(from: StorageOwner.local, to: userID)
        balanceStore.migrateBalance(from: StorageOwner.local, to: userID)
        let migratedDifficulty = userSettingsStore.migrateSettings(from: StorageOwner.local, to: userID)

        if !migratedHabitIDs.isEmpty {
            syncStateStore.markDirty(userID: userID, kind: .habits, ids: migratedHabitIDs)
        }
        if !migratedRewardIDs.isEmpty {
            syncStateStore.markDirty(userID: userID, kind: .rewards, ids: migratedRewardIDs)
        }
        if !migratedTradeIDs.isEmpty {
            syncStateStore.markDirty(userID: userID, kind: .trades, ids: migratedTradeIDs)
        }
        if !migratedTagData.tagIDs.isEmpty {
            syncStateStore.markDirty(userID: userID, kind: .tags, ids: migratedTagData.tagIDs)
        }
        if !migratedTagData.habitTagIDs.isEmpty {
            syncStateStore.markDirty(userID: userID, kind: .habitTags, ids: migratedTagData.habitTagIDs)
        }
        if !migratedTagData.rewardTagIDs.isEmpty {
            syncStateStore.markDirty(userID: userID, kind: .rewardTags, ids: migratedTagData.rewardTagIDs)
        }
        if migratedDifficulty {
            syncStateStore.markDirty(userID: userID, kind: .generalDifficulty, ids: [])
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
        syncStateStore.markDirty(userID: currentUserID, kind: mutation.entityKind, ids: mutation.recordIDs)
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
            let response = try await apiClient.pullSync(since: syncState.lastSync, accessToken: accessToken)
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

        let dirtyHabits = habitStore.getDirtyHabits(ids: dirtySnapshot.habits)
        let dirtyTrades = tradeStore.getDirtyTrades(ids: dirtySnapshot.trades)
        let dirtyTags = tagStore.getDirtyTags(ids: dirtySnapshot.tags)
        let dirtyHabitTags = tagStore.getDirtyHabitTags(ids: dirtySnapshot.habitTags)
        let dirtyRewards = rewardStore.getDirtyRewards(ids: dirtySnapshot.rewards)
        let dirtyRewardTags = tagStore.getDirtyRewardTags(ids: dirtySnapshot.rewardTags)
        let generalDifficultyDirty = syncState.dirty.generalDifficulty

        do {
            let pullResponse = try await apiClient.pullSync(since: syncState.lastSync, accessToken: accessToken)
            applyPullResponse(pullResponse, filteringDirtyState: nil)

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

                let pushResponse = try await apiClient.pushSync(pushRequest, accessToken: accessToken)
                applyPushResponse(pushResponse)
            }

            let serverTime = AppDateCoding.parseBackendTimestamp(pullResponse.serverTime) ?? Date()
            syncStateStore.clearAllDirty(userID: currentUserID)
            syncStateStore.setLastSync(userID: currentUserID, serverTime: serverTime)
            lastSyncTime = serverTime

            habitStore.purgeDeletedHabits()
            tradeStore.purgeDeletedTrades()
            tagStore.purgeDeleted()
            rewardStore.purgeDeletedRewards()

            status = .synced

            if syncState.lastSync == nil || syncStateStore.shouldPerformFullSync(userID: currentUserID, now: serverTime) {
                syncStateStore.recordFullSync(userID: currentUserID, completedAt: serverTime)
            }
        } catch {
            let message = (error as? ApiError)?.userFacingMessage
                ?? (error as? LocalizedError)?.errorDescription
                ?? "Sync failed."
            lastErrorMessage = message
            status = .error(message)
        }

        isSyncing = false
    }

    private func applyPullResponse(_ response: SyncResponse, filteringDirtyState dirtyState: SyncStateStore.UserSyncState?) {
        let dirtyIDs: DirtyIDSnapshot
        if let dirtyState {
            dirtyIDs = makeDirtyIDSnapshot(from: dirtyState)
        } else {
            dirtyIDs = DirtyIDSnapshot()
        }

        let habits: [Habit] = response.habits.compactMap { record in
            let model = record.toModel()
            guard let model else { return nil }
            guard !dirtyIDs.habits.contains(model.id) else { return nil }
            return model
        }

        let trades: [Trade] = response.trades.compactMap { record in
            let model = record.toModel()
            guard let model else { return nil }
            guard !dirtyIDs.trades.contains(model.id) else { return nil }
            return model
        }

        let tags: [Tag] = response.tags.compactMap { record in
            let model = record.toModel()
            guard let model else { return nil }
            guard !dirtyIDs.tags.contains(model.id) else { return nil }
            return model
        }

        let habitTags: [HabitTag] = response.habitTags.compactMap { record in
            let model = record.toModel()
            guard let model else { return nil }
            guard !dirtyIDs.habitTags.contains(model.id) else { return nil }
            return model
        }

        let rewards: [Reward] = response.rewards.compactMap { record in
            let model = record.toModel()
            guard let model else { return nil }
            guard !dirtyIDs.rewards.contains(model.id) else { return nil }
            return model
        }

        let rewardTags: [RewardTag] = response.rewardTags.compactMap { record in
            let model = record.toModel()
            guard let model else { return nil }
            guard !dirtyIDs.rewardTags.contains(model.id) else { return nil }
            return model
        }

        if !habits.isEmpty {
            habitStore.mergeHabits(habits)
        }
        if !trades.isEmpty {
            tradeStore.mergeTrades(trades)
        }
        if !tags.isEmpty {
            tagStore.mergeTags(tags)
        }
        if !habitTags.isEmpty {
            tagStore.mergeHabitTags(habitTags)
        }
        if !rewards.isEmpty {
            rewardStore.mergeRewards(rewards)
        }
        if !rewardTags.isEmpty {
            tagStore.mergeRewardTags(rewardTags)
        }

        balanceStore.setBalance(Int(response.balance.tofuBalance.rounded()))

        if !(dirtyState?.dirty.generalDifficulty ?? false) {
            userSettingsStore.setGeneralDifficulty(response.generalDifficulty, shouldNotifySync: false)
        }

        if let serverTime = AppDateCoding.parseBackendTimestamp(response.serverTime), let currentUserID {
            syncStateStore.setLastSync(userID: currentUserID, serverTime: serverTime)
            lastSyncTime = serverTime
        }
    }

    private func applyPushResponse(_ response: SyncResponse) {
        let habits: [Habit] = response.habits.compactMap { $0.toModel() }
        let trades: [Trade] = response.trades.compactMap { $0.toModel() }
        let tags: [Tag] = response.tags.compactMap { $0.toModel() }
        let habitTags: [HabitTag] = response.habitTags.compactMap { $0.toModel() }
        let rewards: [Reward] = response.rewards.compactMap { $0.toModel() }
        let rewardTags: [RewardTag] = response.rewardTags.compactMap { $0.toModel() }

        if !habits.isEmpty {
            habitStore.mergeHabits(habits)
        }
        if !trades.isEmpty {
            tradeStore.mergeTrades(trades)
        }
        if !tags.isEmpty {
            tagStore.mergeTags(tags)
        }
        if !habitTags.isEmpty {
            tagStore.mergeHabitTags(habitTags)
        }
        if !rewards.isEmpty {
            rewardStore.mergeRewards(rewards)
        }
        if !rewardTags.isEmpty {
            tagStore.mergeRewardTags(rewardTags)
        }

        balanceStore.setBalance(Int(response.balance.tofuBalance.rounded()))
        userSettingsStore.setGeneralDifficulty(response.generalDifficulty, shouldNotifySync: false)
    }

    private struct DirtyIDSnapshot {
        var habits = Set<RecordID>()
        var trades = Set<RecordID>()
        var tags = Set<RecordID>()
        var habitTags = Set<RecordID>()
        var rewards = Set<RecordID>()
        var rewardTags = Set<RecordID>()
    }

    private func makeDirtyIDSnapshot(from state: SyncStateStore.UserSyncState) -> DirtyIDSnapshot {
        DirtyIDSnapshot(
            habits: Set(state.dirty.habits),
            trades: Set(state.dirty.trades),
            tags: Set(state.dirty.tags),
            habitTags: Set(state.dirty.habitTags),
            rewards: Set(state.dirty.rewards),
            rewardTags: Set(state.dirty.rewardTags)
        )
    }
}
