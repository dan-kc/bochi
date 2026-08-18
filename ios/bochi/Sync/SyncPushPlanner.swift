import Foundation

// Sync flow: decides whether a manual sync has anything to push and which newer
// local edits must be protected from the server echo.
struct SyncPushPlan {
    let request: SyncPushRequest?
}

enum SyncPushPlanner {
    static func makePlan(
        localState: SyncLocalState,
        themePalettes: BochiThemePalettePreferences,
        themePalettesGeneration: Int64?,
        baseCursor: String
    ) -> SyncPushPlan {
        var operations = SyncOperationBuilder.makeUpsertOperations(from: localState)
        if localState.themePalettesDirty {
            operations.append(
                SyncOperationBuilder.makeThemePalettesOperation(
                    themePalettes: SyncThemePalettes(preferences: themePalettes),
                    generation: themePalettesGeneration ?? 0
                )
            )
        }

        guard !operations.isEmpty else {
            return SyncPushPlan(request: nil)
        }

        return SyncPushPlan(
            request: SyncPushRequest(
                baseCursor: baseCursor,
                operations: operations
            )
        )
    }

    static func dirtyIDsToProtect(
        after current: SyncStateStore.UserSyncState,
        snapshot: SyncStateStore.UserSyncState
    ) -> SyncDirtyIDSnapshot {
        SyncDirtyIDSnapshot.changes(after: current, snapshot: snapshot)
    }

    static func shouldPersistThemePalettes(
        current: SyncStateStore.UserSyncState,
        snapshot: SyncStateStore.UserSyncState
    ) -> Bool {
        guard current.dirty.themePalettesGeneration != nil else { return true }
        return current.dirty.themePalettesGeneration == snapshot.dirty.themePalettesGeneration
    }
}
