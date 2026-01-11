import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";

const DIRTY_TASKS_KEY = "tofustash_dirty_tasks";
const LAST_SYNC_KEY = "tofustash_last_sync";
const LAST_FULL_SYNC_KEY = "tofustash_last_full_sync";

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

// ============ Dirty task tracking ============

export async function getDirtyTaskIds(): Promise<Set<string>> {
  const data = await getItem(DIRTY_TASKS_KEY);
  return new Set(data ? JSON.parse(data) : []);
}

export async function markTaskDirty(taskId: string): Promise<void> {
  const dirtyIds = await getDirtyTaskIds();
  dirtyIds.add(taskId);
  await setItem(DIRTY_TASKS_KEY, JSON.stringify(Array.from(dirtyIds)));
}

export async function clearDirtyFlag(taskId: string): Promise<void> {
  const dirtyIds = await getDirtyTaskIds();
  dirtyIds.delete(taskId);
  await setItem(DIRTY_TASKS_KEY, JSON.stringify(Array.from(dirtyIds)));
}

export async function clearAllDirtyFlags(): Promise<void> {
  await removeItem(DIRTY_TASKS_KEY);
}

export async function markTasksDirty(taskIds: string[]): Promise<void> {
  const dirtyIds = await getDirtyTaskIds();
  for (const id of taskIds) {
    dirtyIds.add(id);
  }
  await setItem(DIRTY_TASKS_KEY, JSON.stringify(Array.from(dirtyIds)));
}

// ============ Last sync timestamp ============

export async function getLastSyncTime(): Promise<string | null> {
  return getItem(LAST_SYNC_KEY);
}

export async function setLastSyncTime(timestamp: string): Promise<void> {
  await setItem(LAST_SYNC_KEY, timestamp);
}

export async function clearLastSyncTime(): Promise<void> {
  await removeItem(LAST_SYNC_KEY);
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
    // Never done a full sync, do one now
    await removeItem(LAST_SYNC_KEY);
    return true;
  }

  const lastFullSyncTime = parseInt(lastFullSync, 10);
  if (now - lastFullSyncTime > FULL_SYNC_INTERVAL_MS) {
    // More than 24 hours since last full sync
    console.log("[Sync] Triggering periodic full sync (last was >24h ago)");
    await removeItem(LAST_SYNC_KEY);
    return true;
  }

  return false;
}

/**
 * Record that a full sync was completed.
 * Should be called after a successful sync when lastSyncTime was null.
 */
export async function recordFullSyncCompleted(): Promise<void> {
  await setItem(LAST_FULL_SYNC_KEY, Date.now().toString());
}
