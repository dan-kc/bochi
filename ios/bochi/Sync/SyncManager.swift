import Foundation

// Sync flow: SwiftUI-facing facade for visible status and owner session; queue
// policy and pull/apply/push execution live in smaller collaborators.
struct SyncSession: Equatable {
    let ownerID: String?
    let revision: Int
}

@Observable
@MainActor
final class SyncManager {
    private let authManager: AuthManager
    private let syncStateStore: SyncStateStore
    private let ownerScopeCoordinator: OwnerScopeCoordinator
    private let ownerMigrationService: SyncOwnerMigrationService
    private let ownerDataDeletionService: OwnerDataDeletionService
    private let taskQueue = SyncTaskQueue()
    private let runExecutor: SyncRunExecutor
    private var currentUserID: String?
    private var currentUserNeedsLocalMigration = false

    private(set) var status: SyncStatus = .idle
    private(set) var lastSyncTime: Date?
    private(set) var lastErrorMessage: String?
    private(set) var syncSession = SyncSession(ownerID: nil, revision: 0)

    init(
        apiClient: SyncAPIClient,
        authManager: AuthManager,
        syncStateStore: SyncStateStore,
        timerStore: TimerStore,
        taskStore: TaskStore,
        taskDependencyStore: TaskDependencyStore,
        rewardDependencyStore: RewardDependencyStore,
        recurringTaskStore: RecurringTaskStore,
        rewardStore: RewardStore,
        tradeStore: TradeStore,
        tagStore: TagStore,
        balanceStore: BalanceStore,
        userSettingsStore: UserSettingsStore,
        reminderStore: ReminderStore,
        listPreferencesStore: ListPreferencesStore
    ) {
        self.authManager = authManager
        self.syncStateStore = syncStateStore
        let ownerScopeCoordinator = OwnerScopeCoordinator(
            timerStore: timerStore,
            taskStore: taskStore,
            taskDependencyStore: taskDependencyStore,
            rewardDependencyStore: rewardDependencyStore,
            recurringTaskStore: recurringTaskStore,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            tagStore: tagStore,
            balanceStore: balanceStore,
            userSettingsStore: userSettingsStore,
            reminderStore: reminderStore,
            listPreferencesStore: listPreferencesStore
        )
        self.ownerScopeCoordinator = ownerScopeCoordinator
        self.ownerDataDeletionService = OwnerDataDeletionService(storageURL: syncStateStore.databaseURL)
        let payloadPersistence = SyncPayloadPersistence(
            syncStateStore: syncStateStore,
            timerStore: timerStore,
            taskStore: taskStore,
            taskDependencyStore: taskDependencyStore,
            rewardDependencyStore: rewardDependencyStore,
            recurringTaskStore: recurringTaskStore,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            tagStore: tagStore,
            ownerScopeCoordinator: ownerScopeCoordinator
        )
        self.ownerMigrationService = SyncOwnerMigrationService(
            syncStateStore: syncStateStore,
            timerStore: timerStore,
            taskStore: taskStore,
            taskDependencyStore: taskDependencyStore,
            rewardDependencyStore: rewardDependencyStore,
            recurringTaskStore: recurringTaskStore,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            tagStore: tagStore,
            userSettingsStore: userSettingsStore,
            reminderStore: reminderStore,
            listPreferencesStore: listPreferencesStore
        )
        let localStateCollector = SyncLocalStateCollector(
            timerStore: timerStore,
            taskStore: taskStore,
            taskDependencyStore: taskDependencyStore,
            rewardDependencyStore: rewardDependencyStore,
            recurringTaskStore: recurringTaskStore,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            tagStore: tagStore
        )
        let responseApplier = SyncResponseApplier(
            payloadPersistence: payloadPersistence,
            balanceStore: balanceStore,
            userSettingsStore: userSettingsStore
        )
        let completionFinalizer = SyncCompletionFinalizer(
            syncStateStore: syncStateStore,
            timerStore: timerStore,
            taskStore: taskStore,
            taskDependencyStore: taskDependencyStore,
            rewardDependencyStore: rewardDependencyStore,
            recurringTaskStore: recurringTaskStore,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            tagStore: tagStore
        )
        self.runExecutor = SyncRunExecutor(
            apiClient: apiClient,
            syncStateStore: syncStateStore,
            userSettingsStore: userSettingsStore,
            ownerScopeCoordinator: ownerScopeCoordinator,
            localStateCollector: localStateCollector,
            responseApplier: responseApplier,
            completionFinalizer: completionFinalizer
        )
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

    func restoreCachedSession(userID: String) {
        guard currentUserID != userID else { return }

        cancelActiveSyncTask()
        currentUserID = userID
        currentUserNeedsLocalMigration = true
        ownerScopeCoordinator.setCurrentOwner(userID)

        let syncState = syncStateStore.state(for: userID)
        lastSyncTime = syncState.lastSyncTime
        if case .error = status {
            // Keep the last error visible until the next sync attempt updates it.
        } else {
            status = .idle
        }
    }

    func syncNow() async {
        await taskQueue.startManualSync { [weak self] runID in
            await self?.executeSync(runID: runID)
        }.value
    }

    func pullRemoteChangesNow(for userID: String) async {
        guard currentUserID == userID else { return }
        await taskQueue.startBackgroundPull { [weak self] _ in
            await self?.executeBackgroundPull()
        }.value
    }

    func forceFullSyncOnNextRun(for userID: String) {
        guard currentUserID == userID else { return }
        syncStateStore.forceFullSyncOnNextRun(userID: userID)
    }

    func deleteLocalAccountData(for userID: String) throws -> AccountDeletionCleanupResult {
        cancelActiveSyncTask()
        let result = try ownerDataDeletionService.deleteAccountData(userID: userID)
        if currentUserID == userID {
            applySignedOutOwner()
        } else {
            ownerScopeCoordinator.setCurrentOwner(syncSession.ownerID ?? StorageOwner.local)
        }
        return result
    }

    private func applyAuthenticatedOwner(_ userID: String) {
        let previousUserID = currentUserID

        if previousUserID != userID || currentUserNeedsLocalMigration {
            cancelActiveSyncTask()
            migrateLocalDataIfNeeded(to: userID)
        }

        currentUserID = userID
        currentUserNeedsLocalMigration = false
        ownerScopeCoordinator.setCurrentOwner(userID)

        let syncState = syncStateStore.state(for: userID)
        lastSyncTime = syncState.lastSyncTime
        if case .error = status {
            // Keep the last error visible until the next sync attempt updates it.
        } else {
            status = .idle
        }

        publishSyncSession(ownerID: userID)
    }

    private func applySignedOutOwner() {
        cancelActiveSyncTask()
        currentUserID = nil
        currentUserNeedsLocalMigration = false
        ownerScopeCoordinator.setCurrentOwner(StorageOwner.local)
        status = .idle
        lastSyncTime = nil
        lastErrorMessage = nil
        publishSyncSession(ownerID: nil)
    }

    private func publishSyncSession(ownerID: String?) {
        guard syncSession.ownerID != ownerID else { return }
        syncSession = SyncSession(ownerID: ownerID, revision: syncSession.revision + 1)
    }

    private func migrateLocalDataIfNeeded(to userID: String) {
        do {
            try ownerMigrationService.migrateLocalData(to: userID)
        } catch {
            assertionFailure("Failed to migrate local data for sync: \(error)")
        }
    }

    private func cancelActiveSyncTask() {
        taskQueue.cancelAll()
    }

    private func executeBackgroundPull() async {
        guard let userID = currentUserID, let accessToken = authManager.currentAccessTokenForSync() else {
            return
        }

        do {
            if let serverTime = try await runExecutor.executeBackgroundPull(
                userID: userID,
                accessToken: accessToken,
                ensureSessionIsCurrent: { try self.ensureCurrentUserStillMatches(userID) }
            ) {
                lastSyncTime = serverTime
            }
        } catch is CancellationError {
            // Session changes cancel stale background pulls; the new owner will
            // schedule its own sync if needed.
        } catch {
            // Background pulls are intentionally silent so passive polling does
            // not surface noisy errors while the user is offline.
        }
    }

    private func executeSync(runID: UUID) async {
        guard taskQueue.isActiveSyncRun(runID),
            let userID = currentUserID,
            let accessToken = authManager.currentAccessTokenForSync()
        else {
            return
        }

        status = .syncing
        lastErrorMessage = nil

        do {
            lastSyncTime = try await runExecutor.executeManualSync(
                userID: userID,
                accessToken: accessToken,
                ensureSessionIsCurrent: { try self.ensureCurrentUserStillMatches(userID) }
            )

            status = .synced
        } catch is CancellationError {
            if currentUserID == userID, taskQueue.isActiveSyncRun(runID) {
                status = .idle
            }
        } catch {
            guard currentUserID == userID, taskQueue.isActiveSyncRun(runID) else { return }
            let message = (error as? ApiError)?.userFacingMessage
                ?? (error as? LocalizedError)?.errorDescription
                ?? "Sync failed."
            lastErrorMessage = message
            status = .error(message)
        }
    }

    private func ensureCurrentUserStillMatches(_ startedUserID: String) throws {
        guard !Task.isCancelled, currentUserID == startedUserID else {
            throw CancellationError()
        }
    }
}
