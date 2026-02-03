import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import type { SyncState } from "./types";

// How often to force a full sync (24 hours in milliseconds)
const FULL_SYNC_INTERVAL_MS = 24 * 60 * 60 * 1000;

// ============ Platform-aware storage helpers ============

async function getItem(key: string): Promise<string | null> {
  if (Platform.OS === "web") {
    return localStorage.getItem(key);
  }
  return AsyncStorage.getItem(key);
}

async function setItem(key: string, value: string): Promise<void> {
  if (Platform.OS === "web") {
    localStorage.setItem(key, value);
    return;
  }
  await AsyncStorage.setItem(key, value);
}

async function removeItem(key: string): Promise<void> {
  if (Platform.OS === "web") {
    localStorage.removeItem(key);
    return;
  }
  await AsyncStorage.removeItem(key);
}

// ============ Unified Sync State ============

const SYNC_STATE_KEY = "tofustash_sync_state";
const LAST_FULL_SYNC_KEY = "tofustash_last_full_sync";

export function getDefaultSyncState(): SyncState {
  return {
    lastSync: null,
    dirty: {
      habits: [],
      trades: [],
    },
  };
}

/**
 * Parse and migrate sync state from raw JSON string.
 * Handles migrations from older schema versions.
 * Exported for testing.
 */
export function parseSyncState(data: string | null): SyncState {
  if (!data) {
    return getDefaultSyncState();
  }
  try {
    const parsed = JSON.parse(data) as SyncState;
    // Migrate old 'tasks' key to 'habits' if present
    const dirtyWithLegacy = parsed.dirty as unknown as { tasks?: string[]; habits?: string[]; trades?: string[] };
    if (dirtyWithLegacy.tasks) {
      parsed.dirty.habits = dirtyWithLegacy.tasks;
      delete dirtyWithLegacy.tasks;
    }
    // Ensure dirty arrays exist (migration safety)
    parsed.dirty.habits = parsed.dirty.habits ?? [];
    parsed.dirty.trades = parsed.dirty.trades ?? [];
    return parsed;
  } catch {
    return getDefaultSyncState();
  }
}

export async function getSyncState(): Promise<SyncState> {
  const data = await getItem(SYNC_STATE_KEY);
  return parseSyncState(data);
}

export async function setSyncState(state: SyncState): Promise<void> {
  await setItem(SYNC_STATE_KEY, JSON.stringify(state));
}

export async function markDirty(
  entityType: "habits" | "trades",
  id: string,
): Promise<void> {
  const state = await getSyncState();
  if (!state.dirty[entityType].includes(id)) {
    state.dirty[entityType].push(id);
    await setSyncState(state);
  }
}

export async function markManyDirty(
  entityType: "habits" | "trades",
  ids: string[],
): Promise<void> {
  const state = await getSyncState();
  let changed = false;
  for (const id of ids) {
    if (!state.dirty[entityType].includes(id)) {
      state.dirty[entityType].push(id);
      changed = true;
    }
  }
  if (changed) {
    await setSyncState(state);
  }
}

export async function getDirtyIds(
  entityType: "habits" | "trades",
): Promise<Set<string>> {
  const state = await getSyncState();
  return new Set(state.dirty[entityType]);
}

export async function clearAllDirty(): Promise<void> {
  const state = await getSyncState();
  state.dirty = { habits: [], trades: [] };
  await setSyncState(state);
}

export async function getLastSyncTime(): Promise<string | null> {
  const state = await getSyncState();
  return state.lastSync;
}

export async function setLastSyncTime(timestamp: string): Promise<void> {
  const state = await getSyncState();
  state.lastSync = timestamp;
  await setSyncState(state);
}

export async function clearLastSyncTime(): Promise<void> {
  const state = await getSyncState();
  state.lastSync = null;
  await setSyncState(state);
}

// ============ Full sync tracking ============

/**
 * Check if a full sync is needed (more than 24 hours since last full sync).
 * If needed, clears lastSyncTime to force a full pull.
 * Returns true if a full sync will be performed.
 */
export async function checkAndPrepareFullSyncIfNeeded(): Promise<boolean> {
  const lastFullSync = await getItem(LAST_FULL_SYNC_KEY);
  const now = Date.now();

  if (!lastFullSync) {
    await clearLastSyncTime();
    return true;
  }

  const lastFullSyncTime = parseInt(lastFullSync, 10);
  if (now - lastFullSyncTime > FULL_SYNC_INTERVAL_MS) {
    console.log("[Sync] Triggering periodic full sync (last was >24h ago)");
    await clearLastSyncTime();
    return true;
  }

  return false;
}

/**
 * Record that a full sync was completed.
 */
export async function recordFullSyncCompleted(): Promise<void> {
  await setItem(LAST_FULL_SYNC_KEY, Date.now().toString());
}

/**
 * Clear the full sync timestamp, forcing the next sync to be a full sync.
 */
export async function clearFullSyncTimestamp(): Promise<void> {
  await removeItem(LAST_FULL_SYNC_KEY);
}

// ============ Cleanup old storage keys ============

/**
 * Remove old storage keys from previous sync implementation.
 * Call this on app start to clean up.
 */
export async function cleanupOldSyncStorage(): Promise<void> {
  const oldKeys = [
    "tofustash_last_sync",
    "tofustash_trade_last_sync",
    "tofustash_dirty_tasks",
    "tofustash_dirty_trades",
    "tofustash_tasks", // Old tasks storage key
  ];
  for (const key of oldKeys) {
    await removeItem(key);
  }
}

// ============ Habit exports ============

export async function getDirtyHabitIds(): Promise<Set<string>> {
  return getDirtyIds("habits");
}

export async function markHabitDirty(id: string): Promise<void> {
  return markDirty("habits", id);
}

export async function markHabitsDirty(ids: string[]): Promise<void> {
  return markManyDirty("habits", ids);
}

export async function clearDirtyFlag(_id: string): Promise<void> {
  // Individual clear not used in new implementation
  // Dirty flags are cleared all at once after successful sync
}

export async function clearAllDirtyFlags(): Promise<void> {
  return clearAllDirty();
}

// ============ Trade exports ============

export async function getDirtyTradeIds(): Promise<Set<string>> {
  return getDirtyIds("trades");
}

export async function markTradeDirty(id: string): Promise<void> {
  return markDirty("trades", id);
}

export async function markTradesDirty(ids: string[]): Promise<void> {
  return markManyDirty("trades", ids);
}

export async function clearTradeDirtyFlag(_id: string): Promise<void> {
  // Individual clear not used in new implementation
}

export async function clearAllTradeDirtyFlags(): Promise<void> {
  // In unified model, all dirty flags are cleared together
  // This is called separately but now does nothing since clearAllDirty handles both
}

export async function getTradeLastSyncTime(): Promise<string | null> {
  // In unified model, there's only one sync time
  return getLastSyncTime();
}

export async function setTradeLastSyncTime(_timestamp: string): Promise<void> {
  // In unified model, there's only one sync time
  // The main setLastSyncTime handles this
}

export async function clearTradeLastSyncTime(): Promise<void> {
  // In unified model, there's only one sync time
}
