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
- Clears `LAST_FULL_SYNC_KEY` from storage
- Next sync will see no full sync record → forces full sync

### 3. Debounced Push (2-second debounce)
- Triggered by `notifyChange()` after local create/update/delete
- Resets timer on each call, batches rapid edits

### 4. Manual Sync
- `triggerSync()` - immediate sync
- `syncAndWait()` - sync and return promise when complete

### 5. Login Sync
- Clears `lastSyncTime` if user changed
- Forces full pull on authentication

### 6. Tab/App Resume
- Web: storage event or visibility change
- Mobile: app state becomes "active"
- Reloads from persistent storage

---

## Imperative Sync Steps

When `executeSync()` runs:

### Step 0: Check If Full Sync Needed
1. Read `LAST_FULL_SYNC_KEY` from storage
2. Clear `lastSyncTime` (forcing full sync) if ANY of:
   - `LAST_FULL_SYNC_KEY` doesn't exist (first sync ever)
   - More than 24 hours since last full sync
   - User switched accounts (handled in SyncContext)
   - 24-hour reset timer fired (clears `LAST_FULL_SYNC_KEY`)

### Step 1: Pull Remote Changes
1. Call `api.pullTasks(lastSync)`
2. If `lastSync === null` → server returns ALL tasks
3. If `lastSync !== null` → server returns only tasks modified since

### Step 2: Merge Server Tasks
1. If `pullResponse.tasks.length > 0`:
   - Call `taskStore.mergeTasks(pullResponse.tasks)`
   - Updates in-memory store
   - Persists to AsyncStorage/localStorage
   - Notifies React subscribers

### Step 3: Push Dirty Local Tasks
1. Get dirty task IDs from `getDirtyTaskIds()`
2. Get task objects from `taskStore.getDirtyTasks(dirtyIds)`
3. If dirty tasks exist:
   - Call `api.pushTasks(dirtyTasks)`
   - Receive server-resolved versions
   - Merge resolved tasks back into store

### Step 4: Clean Up Local State
1. Call `clearAllDirtyFlags()`
2. Call `taskStore.purgeDeletedTasks()`

### Step 5: Update Sync Timestamp
1. Store `pullResponse.server_time` as `lastSyncTime`
2. Set status to `"synced"`
3. Trigger `onSyncComplete` callback

### Step 6: Record Full Sync
1. If this was a full sync → record timestamp in `LAST_FULL_SYNC_KEY`

---

## Background Pull Steps

When `executeBackgroundPull()` runs:

1. Skip if already syncing
2. Call `api.pullTasks(lastSync)`
3. If tasks returned → merge into store
4. Update `lastSyncTime`
5. Silent failure on error (no status change)

---

## Dirty Flag Flow

1. User modifies task locally
2. Task ID added to `tofustash_dirty_tasks` set
3. `notifyChange()` called → debounce timer starts
4. After 2s idle → `executeSync()` runs
5. Dirty tasks pushed to server
6. `clearAllDirtyFlags()` removes all dirty markers

---

## Storage Keys

| Key | Contents |
|-----|----------|
| `tofustash_dirty_tasks` | JSON array of modified task IDs |
| `tofustash_last_sync` | ISO datetime of last sync |
| `tofustash_last_full_sync` | Milliseconds timestamp of last full sync |
| `tofustash_tasks` | Complete task data |

---

## GraphQL Endpoints

### Pull Query
```graphql
query SyncPull($since: NaiveDateTime) {
  syncPull(since: $since) {
    tasks { id, name, ... }
    server_time
  }
}
```

### Push Mutation
```graphql
mutation SyncPush($tasks: [SyncTaskInput!]!) {
  syncPush(tasks: $tasks) {
    tasks { id, name, ... }
    server_time
  }
}
```

---

## Full Sync vs Incremental Sync

### Incremental Sync
- `lastSyncTime` exists
- Server returns only tasks modified since that timestamp
- Fast, minimal data transfer

### Full Sync
- `lastSyncTime` is null
- Server returns ALL tasks for the user
- `mergeTasks()` adds any missing entries to local store
- Existing local entries are updated with server data

**Recovery scenario:** If local `tofustash_tasks` JSON is missing entries (e.g., cleared storage, corrupted data, new device), a full sync restores them:

1. Server returns complete task list
2. `mergeTasks()` iterates each server task
3. Tasks not in local `allIds` are added
4. Tasks already local are updated
5. Result: local store matches server

---

## Conflict Resolution

- Server-side last-write-wins based on `updated_at`
- Server returns resolved version after push
- Client merges server's version back into store
