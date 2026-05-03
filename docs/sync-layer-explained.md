# Sync Layer Explained

This document is not meant to be a short reference.

It is meant to teach the sync layer from first principles, step by step, using the actual implementation in this repository. The goal is that you should be able to read this top to bottom once and then explain:

- what problem the sync layer is solving
- why the app stores data the way it does
- how local mutations become synced backend state
- how pull and push interact
- where balance comes from
- how deletes work
- which tradeoffs and edge cases exist in the current design

If you want the shorter reference version, read [ios-sync-layer.md](/home/daniel/projects/tofustash/docs/ios-sync-layer.md). If you want the full mental model, read this document.

## 1. The Problem We Are Trying To Solve

Before looking at code, it is worth being explicit about the product problem.

This app wants all of the following to be true at the same time:

- A signed-out user can create habits, rewards, trades, tags, and gameplay settings.
- That signed-out data survives app relaunch.
- If the user later signs in, their existing local data should not be thrown away.
- Once signed in, the user should be able to use multiple devices.
- The UI should not need one codepath for local mode and a different codepath for synced mode.
- Local edits should feel immediate, not blocked on the network.

These requirements pull in different directions.

If the backend were the only source of truth, signed-out use would be poor or impossible.

If local storage were the only source of truth, multi-device sync would be impossible.

If the app used a different data model for signed-out mode versus signed-in mode, the UI and stores would become much more complicated.

So the sync layer is trying to solve a very specific problem:

> How do we keep one local-first app model that works while signed out, then smoothly upgrade that same model into synced account data when the user authenticates?

That question drives almost every design choice below.

## 2. The Core Mental Model

### What are we trying to solve?

We need one app that behaves well in two ownership modes:

- local-only
- authenticated and synced

### Why this design?

Instead of inventing two separate app states, the app uses the same domain model in both cases. The difference is not the type of data. The difference is who owns the data.

That leads to the most important concept in the sync layer:

> Local app state and synced account state are the same kinds of records, but they may belong to different owners.

The app currently uses two owner categories:

- `local-device`
- an authenticated backend user id such as `9d6d4c7e-4d0f-4c8b-bb6d-7b4f9d3a1111`

That means the app can store:

- local unsigned data under `local-device`
- synced account data under a real backend user id

Both use the same stores and the same UI.

This is the conceptual breakthrough that keeps the rest of the system manageable.

## 3. The Main Pieces In The System

### What are we trying to solve?

Before following any flows, we need to know which components own which responsibilities.

### Why this design?

The sync layer works because local persistence, mutation tracking, network calls, and reconciliation are kept separate.

The important pieces are:

- `SyncManager`
- `SyncStateStore`
- `SyncMutationCenter`
- domain stores such as `HabitStore`, `TradeStore`, `RewardStore`, `TagStore`
- projection stores such as `BalanceStore`
- backend `/api/v1/sync`

Here is the simplified division of responsibility.

### `SyncManager`

This is the coordinator.

It decides:

- which owner is active
- when sync should run
- whether a run is full or incremental
- what local dirty data should be pushed
- how pulled data gets merged
- when local soft-deleted rows should be purged

If you want to understand the runtime behavior of sync, this is the most important file:

- [ios/tofustash/Sync/SyncManager.swift](/home/daniel/projects/tofustash/ios/tofustash/Sync/SyncManager.swift)

### `SyncStateStore`

This stores sync metadata per authenticated user:

- `lastSyncCursor`
- `lastSyncTime`
- `lastFullSyncAt`
- versioned dirty ids for each synced entity kind
- a versioned dirty flag for `generalDifficulty`

This metadata is local only. It is not itself part of the backend sync payload.

### `SyncMutationCenter`

This is the bridge between domain stores and `SyncManager`.

The stores do not call the backend directly. Instead, when a synced thing changes, a store posts a mutation notification containing:

- owner id
- entity kind
- record ids

When the current owner is signed in, the store also persists the domain-row mutation and the matching dirty metadata in the same SQLite transaction. `SyncManager` listens only to schedule sync after that durable local commit.

That separation keeps UI and store mutation code simple.

### Domain stores

These hold the actual app records:

- habits
- trades
- rewards
- tags
- habit-tag links
- reward-tag links
- user settings such as `generalDifficulty`

These stores own local persistence and local business behavior.

They do not own network sync orchestration.

### Projection stores

`BalanceStore` is the main example.

Balance is shown locally and persisted locally, but the canonical synced truth is not "a balance row." The backend derives balance by summing trades.

This distinction matters a lot later.

### Backend `/api/v1/sync`

The backend exposes two sync operations:

- `GET /api/v1/sync`
- `POST /api/v1/sync`

The backend handles:

- fetching changed rows
- validating pushed input
- writing pushed rows atomically
- calculating derived balance
- returning canonical rows and metadata

The implementation lives here:

- [backend/src/api/sync.rs](/home/daniel/projects/tofustash/backend/src/api/sync.rs)

## 4. What Is Stored Locally On iOS

### What are we trying to solve?

We need signed-out data to survive relaunch, and we need signed-in data to remain available even when offline.

### Why this design?

The app now persists local state in one SQLite database, accessed through GRDB, instead of one JSON file per store. The database lives at:

- `Application Support/tofustash/tofustash.sqlite`

The key idea did not change:

- the data is still owner-scoped
- signed-out rows still belong to `local-device`
- signed-in rows still belong to a backend user id

What changed is the storage substrate. Instead of keeping separate owner-grouped JSON blobs, the app stores normalized rows with an explicit `owner_id`.

### 4.1 Which tables are synced domain state?

These tables contain synced entities or synced user settings:

- `habits`
- `rewards`
- `trades`
- `tags`
- `habit_tags`
- `reward_tags`
- `user_settings`

These are the rows that can be pulled from the backend, pushed to the backend, or migrated from `local-device` to an authenticated owner.

### 4.2 Which tables are local projections or local metadata?

These are persisted locally but are not first-class synced entities:

- `balance_projections`
- `sync_state`
- `dirty_records`
- `dirty_flags`
- `list_preferences`

That distinction is important:

- `balance_projections` is a local cached projection
- `sync_state`, `dirty_records`, and `dirty_flags` are local control data for sync
- `list_preferences` is UI preference state

### 4.3 Example: rows in `habits`

```json
[
  {
    "id": "local-habit-1",
    "owner_id": "local-device",
    "name": "Walk",
    "description": "",
    "created_at": 1777194000,
    "updated_at": 1777194000,
    "deleted_at": null,
    "min_daily_frequency": 1,
    "difficulty_tier": "medium",
    "duration_seconds": 900,
    "lockout_duration_seconds": null,
    "benefit": null
  },
  {
    "id": "habit-1",
    "owner_id": "9d6d4c7e-4d0f-4c8b-bb6d-7b4f9d3a1111",
    "name": "Deep Work",
    "description": "45 min",
    "created_at": 1777104000,
    "updated_at": 1777199340,
    "deleted_at": null,
    "min_daily_frequency": 2,
    "difficulty_tier": "hard",
    "duration_seconds": 2700,
    "lockout_duration_seconds": 3600,
    "benefit": 1
  }
]
```

Notice what this buys us:

- the same store can serve signed-out and signed-in data
- switching owners is mostly a query/filter change, not a data-model change

### 4.4 Example: rows in `trades`

```json
[
  {
    "id": "trade-1",
    "owner_id": "9d6d4c7e-4d0f-4c8b-bb6d-7b4f9d3a1111",
    "habit_id": "habit-1",
    "reward_id": null,
    "amount": 250,
    "created_at": 1777199370,
    "updated_at": 1777199370,
    "deleted_at": null
  },
  {
    "id": "trade-2",
    "owner_id": "9d6d4c7e-4d0f-4c8b-bb6d-7b4f9d3a1111",
    "habit_id": null,
    "reward_id": "reward-1",
    "amount": -120,
    "created_at": 1777199520,
    "updated_at": 1777199520,
    "deleted_at": null
  }
]
```

Trades are central to the model because they are the actual event history of earning and spending tofu.

### 4.5 Example: rows in `balance_projections`

```json
[
  {
    "owner_id": "local-device",
    "balance": 500,
    "updated_at": 1777199520
  },
  {
    "owner_id": "9d6d4c7e-4d0f-4c8b-bb6d-7b4f9d3a1111",
    "balance": 130,
    "updated_at": 1777199520
  }
]
```

This table is easy to misunderstand.

The app absolutely does persist balance locally.

But that does **not** mean balance is a first-class synced entity. It is a cached local projection that is recalculated from local trades and also overwritten by server-derived balance during sync responses.

### 4.6 Example: rows in sync metadata tables

`sync_state`:

```json
[
  {
    "user_id": "9d6d4c7e-4d0f-4c8b-bb6d-7b4f9d3a1111",
    "last_sync_server_time": 1777199400,
    "last_full_sync_at": 1777199400,
    "full_sync_required": 0
  }
]
```

`dirty_records`:

```json
[
  {
    "user_id": "9d6d4c7e-4d0f-4c8b-bb6d-7b4f9d3a1111",
    "entity_kind": "habits",
    "record_id": "habit-1"
  },
  {
    "user_id": "9d6d4c7e-4d0f-4c8b-bb6d-7b4f9d3a1111",
    "entity_kind": "trades",
    "record_id": "trade-1"
  }
]
```

`dirty_flags`:

```json
[
  {
    "user_id": "9d6d4c7e-4d0f-4c8b-bb6d-7b4f9d3a1111",
    "entity_kind": "generalDifficulty"
  }
]
```

This is not user data. This is sync bookkeeping.

It answers questions such as:

- What was the last checkpoint from the server?
- Which local records still need to be pushed?
- Should the next run be full or incremental?

## 5. Owner Switching: The Foundation Of The Whole Design

### What are we trying to solve?

We need the same UI and stores to work in signed-out mode and signed-in mode, and we need sign-in to preserve local work.

### Why this design?

Instead of copying data into a separate app state tree, the app changes the active owner across all stores.

At app root, `SyncManager.updateSession(userID:)` is wired to `AuthManager.user?.id`.

That means auth changes directly control sync ownership.

### 5.1 Signed out

When there is no authenticated user:

- the active owner becomes `local-device`
- lifecycle sync tasks are cancelled
- sync status resets to idle
- local data remains available and editable

In this state, the app is still fully usable. It is just not syncing with the backend.

### 5.2 Signed in

When a user appears:

1. `SyncManager` detects the authenticated user id.
2. It migrates any `local-device` records into that user id.
3. It marks those migrated record ids dirty.
4. It switches every store to that authenticated owner.
5. It forces a full sync.
6. It starts background lifecycle tasks.

This solves the product requirement:

> A user can create data before account creation, then sign in later without losing that work.

### 5.3 Example: local-to-account migration

Suppose the device has this signed-out row in `habits`:

```json
[
  {
    "id": "local-habit-1",
    "owner_id": "local-device",
    "name": "Stretch",
    "description": "",
    "created_at": 1777194000,
    "updated_at": 1777194000,
    "deleted_at": null,
    "min_daily_frequency": 1,
    "difficulty_tier": "light",
    "duration_seconds": null,
    "lockout_duration_seconds": null,
    "commitment": null
  }
]
```

After sign-in, the store migrates it by changing the owner to the backend user:

```json
[
  {
    "id": "local-habit-1",
    "owner_id": "user-123",
    "name": "Stretch",
    "description": "",
    "created_at": 1777194000,
    "updated_at": 1777194000,
    "deleted_at": null,
    "min_daily_frequency": 1,
    "difficulty_tier": "light",
    "duration_seconds": null,
    "lockout_duration_seconds": null,
    "benefit": null
  }
]
```

And sync metadata is updated to mark the migrated id dirty:

`sync_state`:

```json
[
  {
    "user_id": "user-123",
    "last_sync_server_time": null,
    "last_full_sync_at": null,
    "full_sync_required": 1
  }
]
```

`dirty_records`:

```json
[
  {
    "user_id": "user-123",
    "entity_kind": "habits",
    "record_id": "local-habit-1"
  }
]
```

That is the mechanism that turns "local-only work" into "next sync push this to the backend."

## 6. Dirty Tracking: How The App Knows What To Push

### What are we trying to solve?

If the user changes a local record, how does the app know what needs to be sent to the server?

### Why this design?

The stores own local mutations. The sync coordinator owns network behavior. Dirty tracking is the bridge between them.

The flow is:

1. A store mutates local data.
2. The store posts a `SyncMutation`.
3. `SyncManager` receives that mutation.
4. `SyncStateStore` records the affected ids as dirty.
5. A debounced sync is scheduled.

This means UI code stays simple. A form or button does not need to know how sync works.

### Example: user edits a habit

The user changes a habit name from `"Deep Work"` to `"Focused Work"`.

The local store immediately writes the updated habit:

```json
{
  "id": "habit-1",
  "name": "Focused Work",
  "description": "45 min",
  "createdAt": "2026-04-25T08:00:00.000Z",
  "updatedAt": "2026-04-26T11:00:00.000Z",
  "deletedAt": null,
  "frequency": 2,
  "difficultyTier": "hard",
  "durationSeconds": 2700,
  "lockoutDurationSeconds": 3600,
  "benefit": 1
}
```

Then dirty metadata is updated:

```json
{
  "dirty": {
    "habits": ["habit-1"],
    "trades": [],
    "tags": [],
    "habitTags": [],
    "rewards": [],
    "rewardTags": [],
    "generalDifficulty": false
  }
}
```

Nothing has gone to the backend yet.

This is a key local-first principle:

> Mutation first updates the local app state. Sync happens after.

## 7. Sync Triggers: When Sync Actually Runs

### What are we trying to solve?

We want the app to feel responsive without making a network request for every tiny user action.

### Why this design?

The app uses a mix of debounced push, periodic background pull, full sync reset, and foreground refresh.

### 7.1 Debounced push

Every signed-in local mutation schedules sync after a 6-second debounce.

This batches rapid edits such as:

- typing into a form
- changing several fields in sequence
- toggling multiple tags

The motivation is not only efficiency. It also makes the UI feel less fragile because the user is editing local state, not racing the network on every keystroke.

### 7.2 Background pull

While signed in, the app periodically pulls every 10 seconds.

This is for passive freshness:

- changes from another device
- changes from a web client
- stale data after a pause in app usage

If a sync is already in progress, the background pull is skipped.

Background pull failures are intentionally silent.

### 7.3 App foreground pull

When the app becomes active again, `SyncManager` triggers an immediate background pull.

That covers the common mobile case:

- user leaves app
- another device makes changes
- user returns later

### 7.4 Full sync reset

Every 24 hours, the app forces the next sync to be full by clearing `lastSyncCursor`.

This is a safety mechanism against drift. Even if incremental sync misses something, the app periodically re-anchors against the full backend state.

## 8. The Sync Contract Between iOS And The Backend

### What are we trying to solve?

The app and backend need one shared contract for exchanging changes.

### Why this design?

The sync surface area is intentionally narrow:

- one pull endpoint
- one push endpoint

That keeps the client logic concentrated and makes the backend responsible for transactional consistency.

## 8.1 `GET /api/v1/sync`

This is the pull endpoint.

It accepts:

- optional `cursor`

If `cursor` is present, the backend returns rows that changed after the acknowledged backend snapshot represented by that opaque cursor.

If `cursor` is omitted, the backend returns the full current dataset for that user.

### Example request

```http
GET /api/v1/sync?cursor=eyJ1cHBlcl9ib3VuZF90eF9pZCI6MTIzLCJpbl9wcm9ncmVzc190eF9pZHMiOltdfQ
Authorization: Bearer <access-token>
```

### Example response

```json
{
  "habits": [
    {
      "id": "habit-1",
      "name": "Deep Work",
      "description": "45 min",
      "createdAt": "2026-04-25T08:00:00.000000",
      "updatedAt": "2026-04-26T10:29:00.000000",
      "deletedAt": null,
      "minDailyFrequency": 2,
      "difficultyTier": "hard",
      "durationSeconds": 2700,
      "lockoutDurationSeconds": 3600,
      "benefit": 1
    }
  ],
  "trades": [
    {
      "id": "trade-1",
      "habitId": "habit-1",
      "rewardId": null,
      "amount": 250,
      "createdAt": "2026-04-26T10:29:30.000000",
      "updatedAt": "2026-04-26T10:29:30.000000",
      "deletedAt": null
    }
  ],
  "tags": [],
  "habitTags": [],
  "rewards": [],
  "rewardTags": [],
  "balance": {
    "tofuBalance": 250
  },
  "serverCursor": "eyJ1cHBlcl9ib3VuZF90eF9pZCI6MTI0LCJpbl9wcm9ncmVzc190eF9pZHMiOltdfQ",
  "serverTime": "2026-04-26T10:30:05.000000",
  "email": "user@example.com",
  "isPremium": false,
  "generalDifficulty": 5.0
}
```

Notice that this response contains:

- synced entities
- server-derived balance
- some account-adjacent data

But on iOS, not all of that is treated the same way.

`generalDifficulty` is applied by sync.

`email` and `isPremium` are not used as the primary account truth in the sync layer. `AuthManager` and `/auth/me` remain the main source for auth/account state.

## 8.2 `POST /api/v1/sync`

This is the push endpoint.

The client sends only dirty local entities and settings.

### Example request

```json
{
  "habits": [
    {
      "id": "habit-1",
      "name": "Deep Work",
      "description": "45 min",
      "createdAt": "2026-04-25T08:00:00.000000",
      "updatedAt": "2026-04-26T10:29:00.000000",
      "deletedAt": null,
      "minDailyFrequency": 2,
      "difficultyTier": "hard",
      "durationSeconds": 2700,
      "lockoutDurationSeconds": 3600,
      "benefit": 1
    }
  ],
  "trades": [
    {
      "id": "trade-1",
      "habitId": "habit-1",
      "rewardId": null,
      "amount": 250,
      "createdAt": "2026-04-26T10:29:30.000000",
      "deletedAt": null
    }
  ],
  "generalDifficulty": 5.0
}
```

### Example response

```json
{
  "habits": [
    {
      "id": "habit-1",
      "name": "Deep Work",
      "description": "45 min",
      "createdAt": "2026-04-25T08:00:00.000000",
      "updatedAt": "2026-04-26T10:30:06.000000",
      "deletedAt": null,
      "minDailyFrequency": 2,
      "difficultyTier": "hard",
      "durationSeconds": 2700,
      "lockoutDurationSeconds": 3600,
      "benefit": 1
    }
  ],
  "trades": [
    {
      "id": "trade-1",
      "habitId": "habit-1",
      "rewardId": null,
      "amount": 250,
      "createdAt": "2026-04-26T10:29:30.000000",
      "updatedAt": "2026-04-26T10:30:06.000000",
      "deletedAt": null
    }
  ],
  "tags": [],
  "habitTags": [],
  "rewards": [],
  "rewardTags": [],
  "balance": {
    "tofuBalance": 250
  },
  "serverTime": "2026-04-26T10:30:06.000000",
  "email": "user@example.com",
  "isPremium": false,
  "generalDifficulty": 5.0
}
```

The response gives the client canonical server-written rows and a fresh server-derived balance.

`serverTime` is still useful for UI status, but `serverCursor` is the sync checkpoint.

## 9. Step-By-Step: What Happens During A Normal Signed-In Sync

### What are we trying to solve?

We need the client to safely combine:

- local changes that have not been pushed yet
- remote changes that may have been made elsewhere

### Why this design?

The sync order is carefully chosen to reduce accidental overwrite.

The order is:

1. decide full vs incremental
2. snapshot dirty local state
3. pull remote changes
4. merge pulled changes
5. push dirty local snapshot
6. apply push response
7. update checkpoint and clear dirty state
8. purge local soft-deleted rows

Each step exists for a reason.

### 9.1 Step 1: decide full vs incremental

If `lastSyncCursor` is nil, the next run is full.

If the 24-hour reset has forced a full sync, `lastSyncCursor` is also nil.

Otherwise, the run is incremental.

### 9.2 Step 2: snapshot dirty local state

This is one of the most important decisions in the whole implementation.

Before pulling from the backend, the client snapshots:

- dirty habit rows
- dirty trade rows
- dirty tag rows
- dirty habit-tag rows
- dirty reward rows
- dirty reward-tag rows
- the current dirty generation for `generalDifficulty`

Why?

Because the next pull might include stale server rows for ids that the user has already modified locally. If the app looked up dirty rows only after merging the pull, it could accidentally push the stale version instead of the user’s edit.

So the snapshot preserves the exact local values intended for push and the exact dirty generations that are allowed to be cleared if that sync attempt succeeds.

### 9.3 Step 3: pull remote changes

The app calls:

- full: `GET /api/v1/sync`
- incremental: `GET /api/v1/sync?cursor=<lastSyncCursor>`

### 9.4 Step 4: merge pulled data

There are two different behaviors here.

#### Incremental/background-style merge

Pulled rows are converted to local models and merged into stores.

But for entity ids that are currently dirty locally, the pulled row is skipped. That prevents a passive refresh from stomping unsynced local edits.

#### Full sync merge

For a full sync, the app builds an authoritative current-owner state from:

- the full pulled server dataset
- re-applied dirty local snapshot rows

This is stronger than a normal incremental merge because it can replace stale local leftovers while still preserving unsynced local changes.

### 9.5 Step 5: push dirty local state

If the dirty snapshot contains anything, the app builds one `SyncPushRequest` and sends it to `POST /api/v1/sync`.

It does **not** push every local row. It pushes the dirty subset.

### 9.6 Step 6: apply push response

The backend returns canonical written rows and a recalculated balance.

The app merges those returned rows and updates local projections such as balance.

### 9.7 Step 7: store the new checkpoint

The client takes the response `serverCursor` and records it as the new incremental checkpoint. `serverTime` is stored separately for status UI.

That becomes the next incremental checkpoint.

### 9.8 Step 8: purge local soft-deleted rows

After a successful sync, stores purge locally deleted records from the active local cache.

That means soft delete is used for synchronization, but does not need to remain forever in device storage after success.

## 10. Full Worked Flow: User Claims A Habit While Signed In

### What are we trying to solve?

We want a user action to feel immediate, but we also want the backend to eventually become the durable cross-device truth.

### Why this design?

The app applies the trade and balance locally first, then syncs afterward.

### The flow

1. The user taps claim in the habit trade modal.

2. The UI calculates the reward amount locally.

3. `TradeStore` appends one or more positive trade rows locally.

4. `BalanceStore` immediately increases the visible balance locally.

5. `TradeStore` persists the new trade rows, the balance projection update, and the dirty trade ids in one local SQLite transaction.

6. `TradeStore` posts a `SyncMutation` so `SyncManager` can restart the debounce timer.

7. A debounced sync timer starts.

8. After the debounce, `SyncManager.executeSync()` runs.

9. It snapshots the dirty trade rows.

10. It pulls remote changes from `GET /api/v1/sync`.

11. It merges remote rows, skipping any dirty local trade ids.

12. It sends the dirty local trade rows to `POST /api/v1/sync`.

13. The backend validates the trade references and upserts the trades in a transaction.

14. The backend recalculates balance by summing non-deleted trades.

15. The backend returns the written trades plus authoritative balance.

16. The client merges returned trades and sets local balance from the server response.

17. Only the snapshotted dirty trade generation is cleared.

18. `lastSyncCursor` is advanced to `serverCursor`, and the displayed sync time is updated from `serverTime`.

### Local state before sync

```json
{
  "tradesByOwner": {
    "user-123": [
      {
        "id": "trade-100",
        "habitId": "habit-1",
        "rewardId": null,
        "amount": 250,
        "createdAt": "2026-04-26T10:29:30.000Z",
        "updatedAt": "2026-04-26T10:29:30.000Z",
        "deletedAt": null
      }
    ]
  }
}
```

```json
{
  "balanceByOwner": {
    "user-123": 250
  }
}
```

```json
{
  "statesByUserID": {
    "user-123": {
      "lastSyncCursor": "cursor-123",
      "lastSyncTime": "2026-04-26T10:29:00.000Z",
      "lastFullSyncAt": "2026-04-26T09:00:00.000Z",
      "dirty": {
        "habits": [],
        "trades": [{ "id": "trade-100", "generation": 41 }],
        "tags": [],
        "habitTags": [],
        "rewards": [],
        "rewardTags": [],
        "generalDifficultyGeneration": null
      }
    }
  }
}
```

### Backend effect

The backend stores the trade and returns:

```json
{
  "trades": [
    {
      "id": "trade-100",
      "habitId": "habit-1",
      "rewardId": null,
      "amount": 250,
      "createdAt": "2026-04-26T10:29:30.000000",
      "updatedAt": "2026-04-26T10:29:32.000000",
      "deletedAt": null
    }
  ],
  "balance": {
    "tofuBalance": 250
  },
  "serverCursor": "cursor-124",
  "serverTime": "2026-04-26T10:29:32.000000",
  "habits": [],
  "tags": [],
  "habitTags": [],
  "rewards": [],
  "rewardTags": [],
  "email": "user@example.com",
  "isPremium": false,
  "generalDifficulty": 5.0
}
```

## 11. Full Worked Flow: User Buys A Reward While Signed In

### What are we trying to solve?

The app needs to reflect spending immediately while still letting the backend derive the canonical balance from trades.

### Why this design?

The purchase flow writes a negative trade locally and updates local balance immediately, then sync reconciles against the server-derived balance.

### The flow

1. The user opens the reward purchase UI.

2. Local code computes the price using current reward rules and trade history.

3. If balance is sufficient, `RewardPurchaseService` creates one or more negative trade rows in `TradeStore`.

4. `BalanceStore` immediately subtracts the spent amount.

5. The new trade ids are marked dirty inside the same local transaction that writes the trades.

6. Debounced sync later pushes those negative trades.

7. The backend stores them and recalculates balance from all non-deleted trades.

8. The returned balance replaces the local cached balance.

The important mental model is:

> Spending tofu is represented by trades, not by directly syncing a balance row.

Balance is what the UI shows. Trades are what the backend trusts.

## 12. Full Worked Flow: User Creates Local Data While Signed Out, Then Signs In

### What are we trying to solve?

We want account creation or sign-in to feel like an upgrade, not a reset.

### Why this design?

The app migrates local-device data into the authenticated owner bucket, then pushes it.

### The flow

1. Signed out, the user creates a habit and some trades.

2. Those records are persisted under `local-device`.

3. The user signs in.

4. `SyncManager.updateSession(userID:)` sees a new authenticated owner.

5. Stores migrate data from `local-device` to the authenticated user id.

6. Migrated ids are marked dirty in the same local migration transaction.

7. A full sync is forced by clearing `lastSyncCursor`.

8. `SyncManager` runs a full pull.

9. It rebuilds local current-owner state from the pulled server dataset plus dirty local snapshot records.

10. It pushes the migrated local records.

11. The backend stores them as canonical account data.

12. Future devices can now pull them.

This is why owner-scoped files matter so much. Without them, signed-out local work would be much harder to preserve cleanly.

## 13. Full Worked Flow: Background Pull While The Device Has Dirty Local Changes

### What are we trying to solve?

What if another device changed the same dataset while this device still has unsynced local edits?

### Why this design?

Background pull is allowed to refresh local state, but not for record ids that are dirty locally.

### Example situation

- Device A edits `habit-1` locally but has not pushed yet.
- Device B edits some other habit and syncs.
- Device A’s background pull fires.

### The flow

1. Device A already has `habit-1` marked dirty.

2. Background pull requests `GET /api/v1/sync?cursor=<lastSyncCursor>`.

3. The backend returns all changed rows since that checkpoint cursor.

4. `SyncManager.applyPullResponse(...)` converts those rows to models.

5. For any row whose id is dirty locally, the pulled row is skipped.

6. Non-conflicting pulled rows are merged into local stores.

7. Balance is updated from server response.

8. Local dirty rows remain intact and can still be pushed later.

This is one of the key protections against stale overwrite.

It is not a perfect general conflict-resolution system, but it is a practical local-first safeguard.

## 14. How The Backend Processes Sync

### What are we trying to solve?

The client wants to send one batch of changes and have the backend store them safely and consistently.

### Why this design?

The backend takes a unified push payload and processes it transactionally in dependency order.

## 14.1 Pull behavior

For `GET /api/v1/sync`, the backend:

1. opens one repeatable-read read-only transaction
2. captures a backend snapshot cursor from the current Postgres transaction snapshot
3. loads habits, trades, tags, links, rewards, balance, and profile from that same snapshot
4. when a client cursor is present, filters rows by Postgres transaction id visibility relative to that cursor
5. returns all of that in one response together with a new `serverCursor`

## 14.2 Push behavior

For `POST /api/v1/sync`, the backend:

1. begins a database transaction
2. validates and upserts habits
3. validates and upserts rewards
4. validates and upserts trades
5. validates and upserts tags
6. validates and upserts habit-tag links
7. validates and upserts reward-tag links
8. updates `general_difficulty` if present
9. recalculates balance from trade history
10. commits the transaction
11. loads profile data
12. returns canonical rows plus balance, `serverTime`, and a fresh `serverCursor`

The main reason for this order is dependency safety:

- a trade may reference a habit or reward
- a habit-tag row may reference a habit and a tag
- a reward-tag row may reference a reward and a tag

By the time dependent rows are processed, the parent rows can already exist in the same transaction.

## 14.3 What the backend considers authoritative

The backend is authoritative for:

- persisted synced rows
- `updated_at`
- snapshot checkpoint cursor
- derived balance

The backend is **not** relying on the client’s cached balance as a source of truth.

That is why balance can be repaired by sync even if the local cache was wrong.

## 15. Balance: The Most Common Place To Get Confused

### What are we trying to solve?

Balance is shown constantly in the UI, so it needs to feel immediate. But it also needs a durable cross-device truth.

### Why this design?

The app splits balance behavior into:

- local optimistic display state
- backend-derived canonical state

The visible balance comes from `BalanceStore.balance`.

That value is changed in three ways:

1. immediately by local earning actions
2. immediately by local spending actions
3. overwritten by sync responses from the server

This means the best mental model is:

> Trades are the synced event history. Balance is a local cached projection that is continuously reconciled to server truth.

### 15.1 Local optimistic updates

When claiming a habit:

- `TradeStore` adds positive trade rows
- `BalanceStore.addTofu(...)` updates visible balance immediately

When buying a reward:

- `TradeStore` adds negative trade rows
- `BalanceStore.subtractTofu(...)` updates visible balance immediately

### 15.2 Server reconciliation

Both pull and push responses contain:

```json
{
  "balance": {
    "tofuBalance": 130
  }
}
```

`SyncManager` applies that with `balanceStore.setBalance(...)`.

That means local balance is not just drifting forever. It is repeatedly re-anchored to the backend’s trade-derived value.

### 15.3 Why not just recompute balance from local trades on every render?

This implementation chose a persisted `BalanceStore` projection instead.

That gives:

- fast access everywhere in the UI
- immediate updates from local actions
- survival across relaunch

But it also means balance is one layer removed from the true synced event history.

That tradeoff explains some of the edge cases later.

## 16. Deletes: Soft Delete First, Purge Later

### What are we trying to solve?

Deleting a synced row needs to propagate to the backend and to other devices.

### Why this design?

The app uses soft delete semantics for synced entities. A row is first marked deleted with `deletedAt`, then removed from local storage only after successful sync.

### 16.1 Local delete

If the user deletes a habit locally:

- the habit row stays in the store temporarily
- `deletedAt` is set
- the habit id is marked dirty

That lets the deleted state be pushed to the backend.

### 16.2 After successful sync

After sync completes successfully, local stores purge soft-deleted rows.

So the lifecycle is:

1. active row
2. soft-deleted row with `deletedAt`
3. successful sync
4. purged from local store

### 16.3 Important implication for trades

Deleting a habit does not automatically delete its trade history in the normal app flow.

Trades remain their own records.

That means:

- trade history can still show prior events
- balance still reflects those trade events
- missing source names are rendered as `"Deleted habit"` or `"Deleted reward"` in trade history views

That behavior is consistent with the current implementation.

## 17. Why Full Sync Exists At All

### What are we trying to solve?

Incremental sync is efficient, but it is easier for small inconsistencies or missed records to accumulate over time.

### Why this design?

The app uses incremental sync most of the time, but full sync as a periodic repair and account-transition mechanism.

A full sync matters because it can:

- recover from drift
- remove stale local leftovers
- establish clean initial account state after sign-in
- re-anchor the device against backend truth

The implementation does not just "download everything and replace blindly." It combines the full pulled dataset with dirty local snapshot rows so that unsynced local edits are still preserved.

That hybrid approach is one of the stronger parts of the current design.

## 18. Reliability Hardening And Remaining Tradeoffs

### What are we trying to solve?

No sync system is free of tradeoffs. A useful mental model includes the known sharp edges.

### Why this section matters?

If you only understand the happy path, sync bugs will feel mysterious. If you understand the tradeoffs, behavior that looks odd will make sense immediately.

## 18.1 Dirty changes during an in-flight sync

This used to be one of the more serious correctness risks.

`executeSync()` still snapshots dirty state at the start, but dirty rows now carry a mutation generation.

The sync completion step clears only the exact generations that were present in the snapshot. If the same record is edited again while sync is still in flight, the row gets a newer generation and survives the older clear.

That closes the "same id edited twice during one sync" hole.

## 18.2 Incremental checkpoint safety

The incremental checkpoint is now `serverCursor`, not `serverTime`.

The backend pull path reads all entities inside one repeatable-read snapshot transaction and returns a cursor derived from that snapshot.

That removes the old timing window where rows could be read from one moment and the checkpoint could be generated from a later moment.

The 24-hour full sync still exists as a repair path and account-transition tool, but it is no longer covering for this specific hole.

## 18.3 Balance can temporarily disagree with local trade history during sync

Because balance is not dirty-protected the same way trades are, a pull can temporarily overwrite local optimistic balance with stale server balance before a subsequent push response corrects it.

Usually this is brief and cosmetic.

But conceptually it means:

- trade history is the real synced event history
- visible balance is a reconciled projection

They are related, but not identical at every moment during sync.

## 18.4 Background pull failures are silent

This is a deliberate UX decision.

The benefit is:

- fewer noisy offline errors

The cost is:

- a device can stay stale without loudly warning the user

For a local-first mobile app this is a reasonable tradeoff, but it is still a tradeoff.

## 18.5 Local database corruption or schema issues still need an operational story

Moving to SQLite removes the old "decode failed, return empty JSON state" behavior, which is good.

But it replaces that failure mode with a different operational concern:

- database corruption
- migration bugs
- schema drift during development

For authenticated users, later sync can often repopulate state after recovery.

For signed-out-only local data, a broken local database can still mean apparent data loss with no backend recovery path.

## 18.6 Soft delete semantics need to be understood clearly

Because entities are soft-deleted first and because related histories like trades remain meaningful independently, "delete the habit" does not mean "erase every historical consequence of that habit."

That is coherent with the current model, but it is something the product and engineering sides need to be aligned on.

## 19. A Compact Mental Model To Keep In Your Head

If you forget everything else, remember this:

1. The app is local-first.
2. The same domain model exists in signed-out and signed-in mode.
3. Ownership changes, not the model.
4. Local stores mutate immediately.
5. Dirty tracking decides what needs to be pushed.
6. `SyncManager` coordinates pull, merge, and push.
7. The backend is authoritative for synced rows and derived balance.
8. Trades are the true history of earning and spending.
9. Balance is a local cached projection continuously corrected by sync.
10. Full sync is the repair and re-anchoring mechanism.

## 20. If You Want To Read The Code After This

If you want to connect this explanation back to the implementation, read these in order:

1. [ios/tofustash/Sync/SyncManager.swift](/home/daniel/projects/tofustash/ios/tofustash/Sync/SyncManager.swift)
2. [ios/tofustash/Sync/SyncStateStore.swift](/home/daniel/projects/tofustash/ios/tofustash/Sync/SyncStateStore.swift)
3. [ios/tofustash/Shared/Persistence/AppDatabase.swift](/home/daniel/projects/tofustash/ios/tofustash/Shared/Persistence/AppDatabase.swift)
4. [ios/tofustash/Shared/Persistence/StorageSupport.swift](/home/daniel/projects/tofustash/ios/tofustash/Shared/Persistence/StorageSupport.swift)
4. [ios/tofustash/Habits/HabitStore.swift](/home/daniel/projects/tofustash/ios/tofustash/Habits/HabitStore.swift)
5. [ios/tofustash/Trades/TradeStore.swift](/home/daniel/projects/tofustash/ios/tofustash/Trades/TradeStore.swift)
6. [ios/tofustash/Trades/BalanceStore.swift](/home/daniel/projects/tofustash/ios/tofustash/Trades/BalanceStore.swift)
7. [backend/src/api/sync.rs](/home/daniel/projects/tofustash/backend/src/api/sync.rs)
8. [backend/src/database.rs](/home/daniel/projects/tofustash/backend/src/database.rs)

Read them with this document beside you and the architecture should feel much less abstract.
