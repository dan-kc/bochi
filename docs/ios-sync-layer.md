# iOS Sync Layer

## Purpose

This document explains how the native iOS app in `./ios` now stores local data, tracks dirty state, migrates signed-out data into an account, and syncs with the backend.

The important rule is:

- local app state and synced account state are the same data model, but not always the same owner

The iOS app supports two ownership modes for the same domain objects:

- `local-device`
  - used while signed out
  - data exists only on this device
  - survives relaunch because it is persisted locally

- authenticated backend user id
  - used while signed in
  - data is eligible for sync
  - the backend becomes the durable cross-device source of truth

That lets the app keep the current iOS product decision:

- users can create habits, rewards, tags, trades, and difficulty settings before they create an account

but it also lets the app upgrade into sync later without throwing local work away.

## Design Goals

- Signed-out local-only use must survive relaunch.
- The same SwiftUI screens should work in both signed-out and signed-in modes.
- Sync must match the frontend flow closely enough that both clients behave the same against the same backend contract.
- Local edits must not be overwritten by a stale pull right before push.
- Sync must stay owned by one coordinator instead of being scattered across views.
- Auth/session truth must stay separate from sync truth.

## What Is Persisted

The iOS app now persists these domain collections as JSON in Application Support:

- habits
- rewards
- trades
- tags
- habit-tag links
- reward-tag links
- balances
- user gameplay settings
- sync metadata

The stores are owner-scoped. Each JSON file holds data grouped by owner id instead of only one global array.

That means the same file can contain:

- the signed-out `local-device` dataset
- one or more authenticated datasets keyed by backend user id

SwiftUI still reads simple arrays from each store, but each store exposes only the records for its current owner.

## Owner Switching

The app root wires `SyncManager.updateSession(userID:)` to `AuthManager.user?.id`.

### Signed Out

When there is no authenticated backend user:

- every domain store points at owner `local-device`
- sync timers are stopped
- sync status resets to idle
- local data remains visible and editable

### Signed In

When a backend user exists:

1. `SyncManager` migrates any `local-device` records into that user id
2. migrated ids are marked dirty in sync metadata
3. stores switch to the authenticated owner
4. a full sync is forced
5. background sync timers start

This is the key signed-in upgrade path:

- the user keeps what they created while signed out
- the next authenticated sync pushes it to the backend

## Why Auth State Is Separate

The sync response currently includes:

- `email`
- `isPremium`
- `generalDifficulty`

On iOS:

- `AuthManager` remains the owner of account/session/premium state
- `/auth/me` remains the source of truth for account state
- sync directly applies only domain state plus `generalDifficulty`

That avoids a split-brain situation where entitlement UI could depend on whichever request happened most recently.

## Sync Metadata

`SyncStateStore` persists metadata per authenticated user id:

- `lastSync`
- `lastFullSyncAt`
- dirty ids for:
  - habits
  - trades
  - tags
  - habitTags
  - rewards
  - rewardTags
- dirty flag for:
  - `generalDifficulty`

Signed-out local mode does not use sync metadata because signed-out data is not pushed.

## Dirty Tracking

Stores do not know about the backend directly.

Instead, store mutations post `SyncMutationCenter` notifications containing:

- owner id
- entity kind
- affected ids

`SyncManager` listens for those notifications.

If the mutation belongs to the currently signed-in owner:

1. the matching ids are marked dirty in `SyncStateStore`
2. a 2-second debounce timer is restarted
3. when the user stops editing, sync runs

This keeps the view code simple:

- views keep calling store methods
- sync is added once at the store boundary

## Sync Triggers

The iOS implementation follows the frontend timing model:

### Debounced Push

- Every local create, update, delete, or tag-toggle while signed in posts a mutation.
- The app waits 2 seconds after the last change.
- Then a full sync cycle runs.

This batches rapid edits like:

- typing in forms
- changing frequency then damage
- adding several tags in a row

### Background Pull

- While signed in, the app runs a read-only pull every 5 seconds.
- If a sync is already running, the background pull is skipped.
- Background pull failures are silent.

This is only for passive freshness. It should not surface noisy offline errors.

### Forced Full Sync Reset

- Every 24 hours, the app clears `lastSync` for the signed-in user.
- The next sync becomes a full sync.

This protects against drift where local storage may have missed older records.

### App Foreground

- When the app becomes active again, `SyncManager` runs an immediate background pull.

That covers the normal mobile case where the app was paused while another device made changes.

### Authentication

- Sign-in starts sync.
- Sign-out stops sync.
- Switching accounts forces a full sync for the new account.

## Sync Order

The native flow mirrors the frontend sync order.

### 1. Check Whether Full Sync Is Required

A full sync is forced if:

- there has never been a sync for this user
- the 24-hour reset timer cleared `lastSync`
- the signed-in account changed

### 2. Snapshot Dirty Local State Before Pull

This is one of the most important implementation details.

Before pulling from the backend, the app snapshots:

- dirty habits
- dirty trades
- dirty tags
- dirty habit tags
- dirty rewards
- dirty reward tags
- whether `generalDifficulty` is dirty

Why this matters:

- a stale server record can still be pulled
- pull merge can temporarily overwrite the in-memory copy
- if the app looked up dirty records after merge, it could push the wrong value back

The snapshot guarantees the push uses the user’s original local edit.

### 3. Pull Remote Changes

The app calls:

- `GET /api/sync`
- with `?since=<lastSync>` when incremental
- with no `since` when full

### 4. Merge Pulled Data

For a normal sync, pulled records merge directly into stores.

For a background pull, the app skips remote records whose ids are currently dirty locally.

That means passive refresh will not stomp an unsynced local edit.

### 5. Push Dirty Local State

If any dirty records or dirty settings exist, the app sends one unified request:

- `POST /api/sync`

The payload may include:

- habits
- trades
- tags
- habitTags
- rewards
- rewardTags
- `generalDifficulty`

The backend already owns transactionality and dependency order:

- habits before trades
- rewards before reward-linked trades
- junction records in the same batch

### 6. Merge Server-Resolved Records

The push response is merged back into the same stores.

This is important because the backend is still authoritative for:

- final `updated_at`
- final soft-delete state
- final balance

### 7. Clear Dirty State And Purge Local Tombstones

After a successful sync:

- all dirty markers are cleared
- `lastSync` is updated to `serverTime`
- soft-deleted records are purged from local stores

Purging happens only after a successful sync so deletes are not lost before they reach the backend.

## Conflict Rule

The backend contract still uses last-write-wins based on timestamps.

On iOS, merge rules are:

- when merging server data into a store, newer `updatedAt` wins
- when a record only exists on one side, it is kept
- for tag junctions, the composite key is the identity

The client-side protection is not “invent a custom merge algorithm”.

The protection is:

- snapshot dirty local records before pull
- push those exact snapshots
- then merge the backend’s resolved response

## Composite Key Junction Records

The backend identifies tag assignments by:

- `habitId + tagId`
- `rewardId + tagId`

The iOS app now matches that.

`HabitTag` and `RewardTag` no longer use a separate local UUID as their true identity.

Instead:

- the composite pair is the persisted identity
- SwiftUI still gets `Identifiable` through a computed string id

That keeps the native model aligned with:

- backend tables
- frontend sync payloads
- dirty tracking keys

## What Changed In The Stores

The stores are still the user-facing mutation API for SwiftUI, but they now also:

- load persisted state during initialization
- save after every mutation
- support owner switching
- support local-to-account migration
- merge server records
- expose dirty-record lookup helpers for sync
- purge synced soft deletes

Views still call simple methods like:

- `addHabit`
- `updateReward`
- `deleteTag`
- `addTagToHabit`
- `setGeneralDifficulty`

The sync layer is intentionally hidden behind those store boundaries.

## Settings UI

The Settings screen now shows a lightweight Sync section with:

- current sync status
- last sync time
- current error message, when relevant
- manual `Sync Now`

This is intentionally subtle.

The app does not add a large sync dashboard or redesign the main tabs.

## Tests Added For This Layer

The new behaviour-focused coverage focuses on user workflows:

- local habits persist across relaunch
- signing in after local-only usage migrates and pushes the local data
- dirty local habit fields are snapshotted before pull so stale server data does not erase the pending edit

Those tests are meant to protect the actual workflows a user can hit, not implementation trivia.

## Known Follow-Up Improvements

The current implementation is correct for the existing product direction, but there are a few worthwhile follow-ups:

- remove auth/profile duplication from `/api/sync`
  - `email` and `isPremium` do not need to live in both sync and auth flows

- revisit the 5-second polling interval after launch
  - it matches the frontend today
  - battery/network behaviour may justify relaxing it on mobile later

- add a dedicated restore/recovery story for corrupted local JSON
  - right now the stores fall back to empty/default state if a file cannot be decoded

- consider shared store helpers for owner-scoped persistence
  - the current store code is reasonably DRY
  - a future refactor could extract more generic owner-scoped store infrastructure if these patterns grow further
