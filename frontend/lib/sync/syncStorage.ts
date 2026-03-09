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
      tags: [],
      habitTags: [],
      rewards: [],
      rewardTags: [],
    },
  };
}

/**
 * Parse sync state from raw JSON string.
 * Exported for testing.
 */
export function parseSyncState(data: string | null): SyncState {
  if (!data) {
    return getDefaultSyncState();
  }
  try {
    return JSON.parse(data) as SyncState;
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

type EntityType = "habits" | "trades" | "tags" | "habitTags" | "rewards" | "rewardTags";

export async function markDirty(
  entityType: EntityType,
  id: string,
): Promise<void> {
  const state = await getSyncState();
  // Ensure the array exists (for backwards compatibility with old state)
  if (!state.dirty[entityType]) {
    state.dirty[entityType] = [];
  }
  if (!state.dirty[entityType].includes(id)) {
    state.dirty[entityType].push(id);
    await setSyncState(state);
  }
}

export async function markManyDirty(
  entityType: EntityType,
  ids: string[],
): Promise<void> {
  const state = await getSyncState();
  // Ensure the array exists (for backwards compatibility with old state)
  if (!state.dirty[entityType]) {
    state.dirty[entityType] = [];
  }
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
  entityType: EntityType,
): Promise<Set<string>> {
  const state = await getSyncState();
  return new Set(state.dirty[entityType] || []);
}

export async function clearAllDirty(): Promise<void> {
  const state = await getSyncState();
  state.dirty = { habits: [], trades: [], tags: [], habitTags: [], rewards: [], rewardTags: [], generalDifficulty: false };
  await setSyncState(state);
}

export async function markGeneralDifficultyDirty(): Promise<void> {
  const state = await getSyncState();
  state.dirty.generalDifficulty = true;
  await setSyncState(state);
}

export function isGeneralDifficultyDirty(state: SyncState): boolean {
  return state.dirty.generalDifficulty === true;
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

// ============ Tag exports ============

export async function getDirtyTagIds(): Promise<Set<string>> {
  return getDirtyIds("tags");
}

export async function markTagDirty(id: string): Promise<void> {
  return markDirty("tags", id);
}

export async function markTagsDirty(ids: string[]): Promise<void> {
  return markManyDirty("tags", ids);
}

// ============ HabitTag exports ============

export async function getDirtyHabitTagIds(): Promise<Set<string>> {
  return getDirtyIds("habitTags");
}

export async function markHabitTagDirty(key: string): Promise<void> {
  return markDirty("habitTags", key);
}

export async function markHabitTagsDirty(keys: string[]): Promise<void> {
  return markManyDirty("habitTags", keys);
}

// ============ Reward exports ============

export async function getDirtyRewardIds(): Promise<Set<string>> {
  return getDirtyIds("rewards");
}

export async function markRewardDirty(id: string): Promise<void> {
  return markDirty("rewards", id);
}

export async function markRewardsDirty(ids: string[]): Promise<void> {
  return markManyDirty("rewards", ids);
}

// ============ RewardTag exports ============

export async function getDirtyRewardTagIds(): Promise<Set<string>> {
  return getDirtyIds("rewardTags");
}

export async function markRewardTagDirty(key: string): Promise<void> {
  return markDirty("rewardTags", key);
}

export async function markRewardTagsDirty(keys: string[]): Promise<void> {
  return markManyDirty("rewardTags", keys);
}
