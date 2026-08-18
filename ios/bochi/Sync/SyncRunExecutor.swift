import Foundation

// Sync flow: runs one owner-captured pull/apply/push/finalize sequence; callers
// re-check the session after awaits before any local persistence can happen.
@MainActor
struct SyncRunExecutor {
    private let apiClient: SyncAPIClient
    private let syncStateStore: SyncStateStore
    private let userSettingsStore: UserSettingsStore
    private let ownerScopeCoordinator: OwnerScopeCoordinator
    private let localStateCollector: SyncLocalStateCollector
    private let responseApplier: SyncResponseApplier
    private let completionFinalizer: SyncCompletionFinalizer

    init(
        apiClient: SyncAPIClient,
        syncStateStore: SyncStateStore,
        userSettingsStore: UserSettingsStore,
        ownerScopeCoordinator: OwnerScopeCoordinator,
        localStateCollector: SyncLocalStateCollector,
        responseApplier: SyncResponseApplier,
        completionFinalizer: SyncCompletionFinalizer
    ) {
        self.apiClient = apiClient
        self.syncStateStore = syncStateStore
        self.userSettingsStore = userSettingsStore
        self.ownerScopeCoordinator = ownerScopeCoordinator
        self.localStateCollector = localStateCollector
        self.responseApplier = responseApplier
        self.completionFinalizer = completionFinalizer
    }

    func executeBackgroundPull(
        userID: String,
        accessToken: String,
        ensureSessionIsCurrent: () throws -> Void
    ) async throws -> Date? {
        let syncState = syncStateForNextRun(userID: userID)
        let isFullSync = syncState.lastSyncCursor == nil
        let response = try await apiClient.pullSync(cursor: syncState.lastSyncCursor, accessToken: accessToken)

        try ensureSessionIsCurrent()
        let currentSyncState = syncStateStore.state(for: userID)
        try ensureSessionIsCurrent()

        if isFullSync {
            let localState = localStateCollector.collect(from: currentSyncState)
            try responseApplier.replaceCurrentOwnerStateFromFullPull(
                pullResponse: response,
                localState: localState,
                ownerID: userID
            )
            let serverTime = try updateCheckpointIfPossible(
                response: response,
                userID: userID,
                completedFullSync: true,
                ensureSessionIsCurrent: ensureSessionIsCurrent
            )
            ownerScopeCoordinator.setCurrentOwner(userID)
            return serverTime
        }

        return try applyPullResponse(
            response,
            for: userID,
            filteringDirtyState: currentSyncState,
            updatesCheckpoint: true,
            ensureSessionIsCurrent: ensureSessionIsCurrent
        )
    }

    func executeManualSync(
        userID: String,
        accessToken: String,
        ensureSessionIsCurrent: () throws -> Void
    ) async throws -> Date {
        let syncState = syncStateForNextRun(userID: userID)
        let isFullSync = syncState.lastSyncCursor == nil
        let pullResponse = try await apiClient.pullSync(cursor: syncState.lastSyncCursor, accessToken: accessToken)

        try ensureSessionIsCurrent()
        let syncStateAfterPull = syncStateStore.state(for: userID)
        let localState = localStateCollector.collect(from: syncStateAfterPull)

        if isFullSync {
            try ensureSessionIsCurrent()
            try responseApplier.replaceCurrentOwnerStateFromFullPull(
                pullResponse: pullResponse,
                localState: localState,
                ownerID: userID
            )
        } else {
            try ensureSessionIsCurrent()
            _ = try applyPullResponse(
                pullResponse,
                for: userID,
                filteringDirtyIDs: localState.dirtySnapshot,
                persistsThemePalettes: !localState.themePalettesDirty,
                updatesCheckpoint: false,
                ensureSessionIsCurrent: ensureSessionIsCurrent
            )
        }

        var checkpointResponse = pullResponse
        if localState.hasDirtyChanges {
            let plan = SyncPushPlanner.makePlan(
                localState: localState,
                themePalettes: userSettingsStore.themePalettes,
                themePalettesGeneration: syncStateAfterPull.dirty.themePalettesGeneration,
                baseCursor: pullResponse.serverCursor
            )

            if let pushRequest = plan.request {
                let response = try await apiClient.pushSync(pushRequest, accessToken: accessToken)
                try ensureSessionIsCurrent()
                let dirtyStateBeforeResponse = syncStateStore.state(for: userID)
                let dirtyIDsToProtect = SyncPushPlanner.dirtyIDsToProtect(
                    after: dirtyStateBeforeResponse,
                    snapshot: syncStateAfterPull
                )
                let persistsThemePalettes = SyncPushPlanner.shouldPersistThemePalettes(
                    current: dirtyStateBeforeResponse,
                    snapshot: syncStateAfterPull
                )
                try ensureSessionIsCurrent()
                try responseApplier.applyPushResponse(
                    response,
                    filteringDirtyIDs: dirtyIDsToProtect,
                    persistsThemePalettes: persistsThemePalettes,
                    ownerID: userID
                )
                checkpointResponse = response
            }
        }

        try ensureSessionIsCurrent()
        let serverTime = try completionFinalizer.finalizeSuccessfulSync(
            userID: userID,
            syncStateSnapshot: syncStateAfterPull,
            checkpointResponse: checkpointResponse,
            localState: localState,
            completedFullSync: isFullSync
        )
        try ensureSessionIsCurrent()
        ownerScopeCoordinator.setCurrentOwner(userID)
        return serverTime
    }

    private func syncStateForNextRun(userID: String) -> SyncStateStore.UserSyncState {
        if syncStateStore.shouldPerformFullSync(userID: userID) {
            syncStateStore.forceFullSyncOnNextRun(userID: userID)
        }

        return syncStateStore.state(for: userID)
    }

    private func applyPullResponse(
        _ response: SyncResponse,
        for userID: String,
        filteringDirtyState dirtyState: SyncStateStore.UserSyncState?,
        updatesCheckpoint: Bool,
        ensureSessionIsCurrent: () throws -> Void
    ) throws -> Date? {
        let dirtyIDs: SyncDirtyIDSnapshot
        if let dirtyState {
            dirtyIDs = SyncDirtyIDSnapshot.from(dirtyState)
        } else {
            dirtyIDs = SyncDirtyIDSnapshot()
        }

        return try applyPullResponse(
            response,
            for: userID,
            filteringDirtyIDs: dirtyIDs,
            persistsThemePalettes: !(dirtyState?.dirty.themePalettes ?? false),
            updatesCheckpoint: updatesCheckpoint,
            ensureSessionIsCurrent: ensureSessionIsCurrent
        )
    }

    private func applyPullResponse(
        _ response: SyncResponse,
        for userID: String,
        filteringDirtyIDs dirtyIDs: SyncDirtyIDSnapshot,
        persistsThemePalettes: Bool,
        updatesCheckpoint: Bool,
        ensureSessionIsCurrent: () throws -> Void
    ) throws -> Date? {
        try responseApplier.applyPullResponse(
            response,
            filteringDirtyIDs: dirtyIDs,
            persistsThemePalettes: persistsThemePalettes,
            ownerID: userID
        )

        guard updatesCheckpoint else { return nil }
        return try updateCheckpointIfPossible(
            response: response,
            userID: userID,
            completedFullSync: false,
            ensureSessionIsCurrent: ensureSessionIsCurrent
        )
    }

    private func updateCheckpointIfPossible(
        response: SyncResponse,
        userID: String,
        completedFullSync: Bool,
        ensureSessionIsCurrent: () throws -> Void
    ) throws -> Date? {
        guard let serverTime = AppDateCoding.parseBackendTimestamp(response.serverTime) else {
            return nil
        }

        try ensureSessionIsCurrent()
        try AppDatabase.shared.transaction(at: syncStateStore.databaseURL) { db in
            try self.syncStateStore.updateCheckpoint(
                userID: userID,
                serverCursor: response.serverCursor,
                serverTime: serverTime,
                completedFullSync: completedFullSync,
                on: db
            )
        }
        return serverTime
    }
}
