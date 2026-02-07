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
2. If `lastSyncTime === null` → server returns ALL habits and trades
3. If `lastSyncTime !== null` → server returns only entities modified since

### Step 2: Merge Server Data
1. If habits returned → `habitStore.mergeHabits(response.habits)`
2. If trades returned → `tradeStore.mergeTrades(response.trades)`
3. Update balance from response

### Step 3: Push Dirty Local Entities
1. Get dirty IDs from sync state (`dirtyHabitIds`, `dirtyTradeIds`)
2. Build push payload with dirty habits and trades
3. If any dirty entities exist:
   - Call `api.syncPush(input)` with unified payload
   - Server processes in transaction (habits first, then trades)
   - Receive server-resolved versions
   - Merge resolved entities back into stores

### Step 4: Clean Up Local State
1. Call `clearAllDirty()` to reset dirty tracking
2. Call `habitStore.purgeDeletedHabits()`
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

1. User modifies habit or trade locally
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
| `tofustash_habits` | Complete habit data |
| `tofustash_trades` | Complete trade data |

### Sync State Structure

```typescript
interface SyncState {
  lastSync: string | null;  // ISO datetime of last sync
  dirty: {
    habits: string[];       // Habit IDs pending push
    trades: string[];       // Trade IDs pending push
  };
}
```

---

## REST Endpoints

### Unified Sync
```
POST /sync
Body: { habits?: [...], trades?: [...] }
Query: ?since=<ISO datetime>

Response: {
  habits: [...],
  trades: [...],
  balance: { tofu_balance },
  server_time: "..."
}
```

---

## Unified Sync Benefits

### Atomic Transactions
- All entities pushed in single database transaction
- Partial failures roll back everything
- No inconsistent state between entity types

### Dependency Ordering
- Server processes habits before trades
- Trades can reference habits created in same push
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
- Server returns ALL habits and trades for the user
- `mergeHabits()`/`mergeTrades()` adds any missing entries to local store
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
