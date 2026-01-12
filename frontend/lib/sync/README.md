# Sync System

## Sync Status Events

```
idle → syncing → synced
                ↘ error
```

| Status    | Meaning                          |
|-----------|----------------------------------|
| `idle`    | No sync in progress              |
| `syncing` | Active sync operation            |
| `synced`  | Sync completed successfully      |
| `error`   | Sync failed (includes message)   |

---

## Trigger Events

### 1. Background Pull (every 5 seconds)
- Pulls remote changes only (read-only)
- Silent failure if offline or already syncing

### 2. Full Sync Reset Timer (every 24 hours)
- Clears `lastSyncTime` from state
- Next sync will force full sync

### 3. Debounced Push (2-second debounce)
- Triggered by `notifyChange()` after local create/update/delete
- Resets timer on each call, batches rapid edits

### 4. Manual Sync
- `triggerSync()` - immediate sync
- `syncAndWait()` - sync and return promise when complete

### 5. Login Sync
- Clears sync state if user changed
- Forces full pull on authentication

### 6. Tab/App Resume
- Web: storage event or visibility change
- Mobile: app state becomes "active"
- Reloads from persistent storage

---

## Imperative Sync Steps

When `executeSync()` runs:

### Step 0: Check If Full Sync Needed
1. Read sync state from storage
2. Clear `lastSyncTime` (forcing full sync) if ANY of:
   - `lastSyncTime` doesn't exist (first sync ever)
   - More than 24 hours since last full sync
   - User switched accounts

### Step 1: Pull Remote Changes
1. Call `api.sync(lastSyncTime)`
2. If `lastSyncTime === null` → server returns ALL tasks and trades
3. If `lastSyncTime !== null` → server returns only entities modified since

### Step 2: Merge Server Data
1. If tasks returned → `taskStore.mergeTasks(response.tasks)`
2. If trades returned → `tradeStore.mergeTrades(response.trades)`
3. Update balance from response

### Step 3: Push Dirty Local Entities
1. Get dirty IDs from sync state (`dirtyTaskIds`, `dirtyTradeIds`)
2. Build push payload with dirty tasks and trades
3. If any dirty entities exist:
   - Call `api.syncPush(input)` with unified payload
   - Server processes in transaction (tasks first, then trades)
   - Receive server-resolved versions
   - Merge resolved entities back into stores

### Step 4: Clean Up Local State
1. Call `clearAllDirty()` to reset dirty tracking
2. Call `taskStore.purgeDeletedTasks()`
3. Call `tradeStore.purgeDeletedTrades()`

### Step 5: Update Sync Timestamp
1. Store `response.serverTime` as `lastSyncTime`
2. Set status to `"synced"`
3. Trigger `onSyncComplete` callback

### Step 6: Record Full Sync
1. If this was a full sync → record timestamp in `lastFullSyncTime`

---

## Background Pull Steps

When `executeBackgroundPull()` runs:

1. Skip if already syncing
2. Call `api.sync(lastSyncTime)`
3. If entities returned → merge into stores
4. Update `lastSyncTime`
5. Silent failure on error (no status change)

---

## Dirty Flag Flow

1. User modifies task or trade locally
2. Entity ID added to appropriate dirty set in sync state
3. `notifyChange()` called → debounce timer starts
4. After 2s idle → `executeSync()` runs
5. Dirty entities pushed to server atomically
6. `clearAllDirty()` removes all dirty markers

---

## Storage Keys

| Key | Contents |
|-----|----------|
| `tofustash_sync_state` | JSON object with sync state (see below) |
| `tofustash_tasks` | Complete task data |
| `tofustash_trades` | Complete trade data |

### Sync State Structure

```typescript
interface SyncState {
  lastSyncTime: string | null;      // ISO datetime of last sync
  lastFullSyncTime: number | null;  // Milliseconds timestamp
  dirtyTaskIds: string[];           // Task IDs pending push
  dirtyTradeIds: string[];          // Trade IDs pending push
}
```

---

## GraphQL Endpoints

### Unified Pull Query
```graphql
query Sync($since: NaiveDateTime) {
  sync(since: $since) {
    tasks { id, name, description, ... }
    trades { id, taskId, rewardId, amount, ... }
    balance { soyBalance, tofuBalance }
    serverTime
  }
}
```

### Unified Push Mutation
```graphql
mutation Sync($input: SyncInput!) {
  sync(input: $input) {
    tasks { id, name, ... }
    trades { id, taskId, ... }
    balance { soyBalance, tofuBalance }
    serverTime
  }
}
```

### SyncInput Structure
```graphql
input SyncInput {
  tasks: [SyncTaskInput!]
  trades: [SyncTradeInput!]
}
```

---

## Unified Sync Benefits

### Atomic Transactions
- All entities pushed in single database transaction
- Partial failures roll back everything
- No inconsistent state between entity types

### Dependency Ordering
- Server processes tasks before trades
- Trades can reference tasks created in same push
- Foreign key constraints always satisfied

### Simplified Client Logic
- Single sync timestamp for all entity types
- One API call for push, one for pull
- Consolidated dirty tracking in single state object

---

## Full Sync vs Incremental Sync

### Incremental Sync
- `lastSyncTime` exists
- Server returns only entities modified since that timestamp
- Fast, minimal data transfer

### Full Sync
- `lastSyncTime` is null
- Server returns ALL tasks and trades for the user
- `mergeTasks()`/`mergeTrades()` adds any missing entries to local store
- Existing local entries are updated with server data

**Recovery scenario:** If local storage is missing entries (e.g., cleared storage, corrupted data, new device), a full sync restores them:

1. Server returns complete entity lists
2. Merge functions iterate each server entity
3. Entities not in local store are added
4. Entities already local are updated
5. Result: local store matches server

---

## Conflict Resolution

- Server-side last-write-wins based on `updated_at`
- Server returns resolved version after push
- Client merges server's version back into store

---

## Schema Migration Strategy

Schema changes in a local-first app require coordination across three layers:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Schema Change                            │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│   Database    │    │    Backend    │    │   Frontend    │
│  (Flyway)     │    │  (API Input)  │    │ (Local Store) │
└───────────────┘    └───────────────┘    └───────────────┘
│                    │                    │
│ - Add column       │ - Accept old       │ - normalize()
│ - Set defaults     │   format input     │   transforms
│ - Add constraints  │ - Transform to     │ - Write-back
│                    │   new format       │   persists
└────────────────────┴────────────────────┴─────────────────
```

### The Problem

When you add a new field (e.g., `habit` boolean):

1. **Old database rows** - don't have the field
2. **Old clients** - send data without the field
3. **Old local storage** - has cached data without the field

All three must handle missing data gracefully.

---

### Layer 1: Database Migration (Flyway)

Run a Flyway migration to add the column with a default value:

```sql
-- V75__add_habit_to_tasks.sql
ALTER TABLE tasks ADD COLUMN habit BOOLEAN NOT NULL DEFAULT FALSE;

-- Backfill: tasks with min_daily_frequency were habits
UPDATE tasks SET habit = TRUE WHERE min_daily_frequency IS NOT NULL;

-- Add constraints after backfill
ALTER TABLE tasks ADD CONSTRAINT habit_no_completed_at
  CHECK (NOT (habit = TRUE AND completed_at IS NOT NULL));
ALTER TABLE tasks ADD CONSTRAINT non_habit_no_frequency
  CHECK (NOT (habit = FALSE AND min_daily_frequency IS NOT NULL));
```

**Key principle**: Set sensible defaults and backfill existing rows.

---

### Layer 2: Backend API Compatibility

The sync endpoint must accept data from old clients that don't send the new field.

**Strategy: Transform on ingestion, validate after**

In the GraphQL resolver or service layer, normalize input before validation:

```rust
// In sync mutation handler
fn normalize_task_input(input: SyncTaskInput) -> SyncTaskInput {
    // Infer habit from min_daily_frequency if not provided
    let habit = input.habit.unwrap_or_else(|| input.min_daily_frequency.is_some());

    // Enforce constraint: habits can't have completed_at
    let completed_at = if habit { None } else { input.completed_at };

    SyncTaskInput { habit: Some(habit), completed_at, ..input }
}
```

**Key principles**:
- **Lenient on input**: Accept old formats, missing fields
- **Strict on storage**: Transform to valid current schema before saving
- **Same logic as frontend**: Backend normalize mirrors frontend normalize

---

### Layer 3: Frontend Local Storage

Local-first apps can't run migrations on user devices. Instead, use **normalize functions** that run on every load.

#### How It Works

1. Each entity store has a `normalize()` function
2. When data is loaded from storage, `normalize()` fills in missing fields
3. **After normalizing, data is persisted back** to storage
4. Future loads read already-migrated data

#### Example

```typescript
function normalizeTask(task: Partial<Task>): Task {
  // V1 (2025-01): Added habit field with constraints.
  // Enforce: min_daily_frequency exists → must be habit
  // Enforce: habit → clear completed_at
  const habit = task.min_daily_frequency != null ? true : (task.habit ?? false);
  const completed_at = habit ? null : (task.completed_at ?? null);

  return {
    // ... other fields ...
    habit,
    completed_at,
  };
}
```

#### Key Principles

- **Normalize is idempotent**: Safe to run repeatedly
- **Write-back on load**: `readStorageSync()` persists normalized data
- **Never remove migration logic**: Users may have years-old cached data
- **Enforce constraints**: Don't just fill defaults—fix invalid states

---

### Coordinated Rollout Process

When adding a new field with constraints:

#### Step 1: Database Migration
- Add column with DEFAULT (no constraint yet)
- Backfill existing rows
- Deploy migration

#### Step 2: Backend Update
- Add field to GraphQL input type (optional)
- Add normalize/transform logic to accept old format
- Update validation to enforce constraints
- Deploy backend

#### Step 3: Frontend Update
- Add field to TypeScript type
- Update normalize() with migration logic
- Deploy frontend (web auto-updates, mobile via app stores)

#### Step 4: Add Database Constraints (optional, later)
- Once all clients are updated, add strict DB constraints
- This is optional—backend validation may be sufficient

---

### Deprecation Timeline

For breaking changes that can't be auto-migrated:

1. **Week 0**: Deploy backend that accepts both old and new format
2. **Week 1-4**: Monitor logs for old format usage
3. **Week 4+**: Once old format usage drops to ~0%, consider removing support
4. **Never**: For constraints that can be auto-fixed, keep migration logic forever

---

### Testing Schema Changes

1. **Unit tests**: Test normalize() with old data shapes
2. **Integration tests**: Test sync endpoint with old client payloads
3. **Manual test**: Clear local storage, verify full sync works
4. **Manual test**: Keep old local storage, verify migration works
