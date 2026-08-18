# Sync Layer Code Guide

This is a map for reading the sync code. It intentionally skips broad
architecture exposition; the file headers in `ios/bochi/Sync` explain the local
role of each type.

## Core Invariants

- The app is local-first.
- Signed-out rows belong to `StorageOwner.local` (`local-device`).
- Signed-in rows belong to the backend user id.
- Stores mutate durable local state and mark dirty records.
- SwiftUI lifecycle modifiers trigger sync effects.
- `serverCursor` is the incremental checkpoint.
- `serverRevision` is the per-record conflict/version authority.
- Balance is a projection, not a pushed entity.
- Soft deletes sync first, then purge after successful completion.

## Read In This Order

Root/lifecycle:

- `ios/bochi/bochiApp.swift`
- `ios/bochi/Lifecycles/AuthSessionLifecycle.swift`
- `ios/bochi/Lifecycles/SyncSessionLifecycle.swift`
- `ios/bochi/Lifecycles/SyncMutationLifecycle.swift`
- `ios/bochi/Lifecycles/SyncBackgroundPullLifecycle.swift`
- `ios/bochi/Lifecycles/SyncFullSyncResetLifecycle.swift`
- `ios/bochi/Lifecycles/AppActivationLifecycle.swift`

Coordinator/run path:

- `ios/bochi/Sync/SyncManager.swift`
- `ios/bochi/Sync/SyncTaskQueue.swift`
- `ios/bochi/Sync/SyncRunExecutor.swift`
- `ios/bochi/Sync/SyncPushPlanner.swift`
- `ios/bochi/Sync/SyncCompletionFinalizer.swift`

State/reconciliation:

- `ios/bochi/Sync/SyncStateStore.swift`
- `ios/bochi/Sync/SyncLocalStateCollector.swift`
- `ios/bochi/Sync/SyncDirtyIDSnapshot.swift`
- `ios/bochi/Sync/SyncResponseApplier.swift`
- `ios/bochi/Sync/SyncPayloadPersistence.swift`
- `ios/bochi/Sync/SyncPayload.swift`
- `ios/bochi/Sync/OwnerScopeCoordinator.swift`
- `ios/bochi/Sync/SyncOwnerMigrationService.swift`

Wire format:

- `ios/bochi/Sync/SyncAPIClient.swift`
- `ios/bochi/Sync/SyncModels.swift`
- `ios/bochi/Sync/SyncOperationBuilder.swift`
- `backend/src/api/sync.rs`

Dirty-emitting stores:

- `ios/bochi/Timers/TimerStore.swift`
- `ios/bochi/Tasks/TaskStore.swift`
- `ios/bochi/Tasks/TaskDependencyStore.swift`
- `ios/bochi/RecurringTasks/RecurringTaskStore.swift`
- `ios/bochi/RecurringTasks/TagStore.swift`
- `ios/bochi/Rewards/RewardStore.swift`
- `ios/bochi/Rewards/RewardDependencyStore.swift`
- `ios/bochi/Trades/TradeStore.swift`
- `ios/bochi/Settings/UserSettingsStore.swift`
- `ios/bochi/Shared/Utilities/EntityDeletionService.swift`

## Trigger Path

- Auth changes: `AuthSessionLifecycle` calls `SyncManager.updateSession(userID:)`.
- New signed-in session: `SyncSessionLifecycle` calls `syncNow()`.
- Local mutations: stores post `SyncMutation`; `SyncMutationLifecycle` debounces
  and calls `syncNow()`.
- Passive refresh: `SyncBackgroundPullLifecycle` calls `pullRemoteChangesNow(...)`.
- Daily repair: `SyncFullSyncResetLifecycle` calls `forceFullSyncOnNextRun(...)`.
- Foreground: `AppActivationLifecycle` accrues vault interest, then pulls.

The stores do not call the network. They write local rows, update dirty state,
and publish lightweight mutation events.

## Owner Switching

`SyncManager.updateSession(userID:)` is the auth/sync boundary.

Signed out:

- cancels queued sync work
- switches stores to `local-device`
- clears visible sync status

Signed in:

- cancels stale sync work when the owner changes
- migrates `local-device` rows to the user id
- marks migrated rows dirty
- switches stores to the user id
- publishes a `SyncSession` revision for lifecycle hooks

Read `SyncOwnerMigrationService` and `OwnerScopeCoordinator` together.

## Manual Sync Run

`SyncTaskQueue` ensures only one manual sync is active and serializes it behind
any current background pull.

`SyncRunExecutor.executeManualSync(...)` does the work:

1. decide full vs incremental from `SyncStateStore`
2. pull `/api/v1/sync`
3. verify the auth/session owner is still current
4. snapshot current dirty state with `SyncLocalStateCollector`
5. apply pull response while protecting dirty local rows
6. build operation push request with `SyncPushPlanner`
7. push dirty operations if any exist
8. protect edits made while the push was in flight
9. apply push response
10. finalize checkpoint and clear only the captured dirty generations
11. purge synced tombstones through `SyncCompletionFinalizer`

Full sync uses the pulled server payload as the owner snapshot, then reapplies
dirty local rows before persisting. Incremental sync merges returned rows into
current local state.

## Background Pull Run

`executeBackgroundPull(...)` pulls and applies remote changes, but does not push.

It is intentionally quiet:

- cancellation usually means the owner changed
- errors do not surface in the sync status UI
- full-sync-required state still performs full replacement repair

## Dirty State

`SyncStateStore` owns:

- `sync_state.last_sync_cursor`
- `sync_state.last_sync_server_time`
- `sync_state.last_full_sync_at`
- `sync_state.full_sync_required`
- `dirty_records`
- `dirty_flags`

Dirty rows carry a mutation generation. Completion clears only the generations
captured at the start of the successful run. Edits made during an in-flight sync
survive and are retried.

Theme palettes use `dirty_flags` because they are one account-level setting, not
an entity id list.

## Push Format

The iOS client pushes operation envelopes:

- `operationId`
- `kind`
- `baseRecordRevision`
- `payload`

`SyncOperationBuilder` makes deterministic operation ids from entity kind, record
id, and dirty generation. That keeps retries idempotent.

Supported operation kinds are generated in `SyncOperationBuilder`; backend
handling lives in `backend/src/api/sync.rs`.

## Response Apply

`SyncResponseApplier` handles response semantics.

`SyncPayloadPersistence` handles the mechanical read/merge/write transaction.

Important rules:

- dirty local records are excluded from pull overwrite
- push echoes are authoritative unless a newer local edit appeared in flight
- server balance replaces local balance unless local dirty trades require refresh
- theme palettes are protected like other dirty local state

## Balance

`BalanceStore` is a local projection.

Local actions update it immediately for UX. Sync responses re-anchor it to the
server-derived value. The backend derives balance from trade history; the client
does not push balance as its own entity.

If balance and trade history briefly disagree during sync, trust trades as the
synced event history.

## Deletes

Deletes are tombstones first:

1. store sets `deletedAt`
2. dirty state records the id
3. sync pushes the tombstone
4. successful finalization purges local tombstones

Use `EntityDeletionService` for user deletes that need dependent records
tombstoned consistently.

## Backend Notes

`backend/src/api/sync.rs` handles both pull and push.

Pull:

- accepts optional `cursor`
- returns rows with `serverRevision` greater than that cursor
- returns full current state when cursor is absent
- includes `serverCursor`, `serverTime`, balance, account-adjacent fields, and
  theme palettes

Push:

- validates operations
- checks `baseRecordRevision`
- writes in dependency-safe order
- allocates server revisions transactionally
- stores processed operation responses for idempotency
- recalculates balance
- returns canonical rows and a fresh cursor

## High-Value Tests

- `ios/bochiTests/SyncManagerTests.swift`
- `ios/bochiTests/SyncOperationBuilderTests.swift`
- `ios/bochiTests/SyncPayloadMapperTests.swift`
- `ios/bochiTests/SyncLocalStateCollectorTests.swift`
- `ios/bochiTests/SyncCompletionFinalizerTests.swift`
- `backend/tests/rest/sync.rs`
