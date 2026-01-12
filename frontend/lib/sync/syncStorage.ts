import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";

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

// ============ Generic dirty tracking factory ============

export interface DirtyTracker {
  getDirtyIds(): Promise<Set<string>>;
  markDirty(id: string): Promise<void>;
  markManyDirty(ids: string[]): Promise<void>;
  clearDirtyFlag(id: string): Promise<void>;
  clearAll(): Promise<void>;
}

export function createDirtyTracker(storageKey: string): DirtyTracker {
  async function getDirtyIds(): Promise<Set<string>> {
    const data = await getItem(storageKey);
    return new Set(data ? JSON.parse(data) : []);
  }

  async function markDirty(id: string): Promise<void> {
    const dirtyIds = await getDirtyIds();
    dirtyIds.add(id);
    await setItem(storageKey, JSON.stringify(Array.from(dirtyIds)));
  }

  async function markManyDirty(ids: string[]): Promise<void> {
    const dirtyIds = await getDirtyIds();
    for (const id of ids) {
      dirtyIds.add(id);
    }
    await setItem(storageKey, JSON.stringify(Array.from(dirtyIds)));
  }

  async function clearDirtyFlag(id: string): Promise<void> {
    const dirtyIds = await getDirtyIds();
    dirtyIds.delete(id);
    await setItem(storageKey, JSON.stringify(Array.from(dirtyIds)));
  }

  async function clearAll(): Promise<void> {
    await removeItem(storageKey);
  }

  return { getDirtyIds, markDirty, markManyDirty, clearDirtyFlag, clearAll };
}

// ============ Generic sync timestamp factory ============

export interface SyncTimestamp {
  get(): Promise<string | null>;
  set(timestamp: string): Promise<void>;
  clear(): Promise<void>;
}

export function createSyncTimestamp(storageKey: string): SyncTimestamp {
  return {
    get: () => getItem(storageKey),
    set: (timestamp: string) => setItem(storageKey, timestamp),
    clear: () => removeItem(storageKey),
  };
}

// ============ Task sync tracking ============

const taskDirtyTracker = createDirtyTracker("tofustash_dirty_tasks");
const taskSyncTimestamp = createSyncTimestamp("tofustash_last_sync");

export const getDirtyTaskIds = taskDirtyTracker.getDirtyIds;
export const markTaskDirty = taskDirtyTracker.markDirty;
export const markTasksDirty = taskDirtyTracker.markManyDirty;
export const clearDirtyFlag = taskDirtyTracker.clearDirtyFlag;
export const clearAllDirtyFlags = taskDirtyTracker.clearAll;

export const getLastSyncTime = taskSyncTimestamp.get;
export const setLastSyncTime = taskSyncTimestamp.set;
export const clearLastSyncTime = taskSyncTimestamp.clear;

// ============ Trade sync tracking ============

const tradeDirtyTracker = createDirtyTracker("tofustash_dirty_trades");
const tradeSyncTimestamp = createSyncTimestamp("tofustash_trade_last_sync");

export const getDirtyTradeIds = tradeDirtyTracker.getDirtyIds;
export const markTradeDirty = tradeDirtyTracker.markDirty;
export const markTradesDirty = tradeDirtyTracker.markManyDirty;
export const clearTradeDirtyFlag = tradeDirtyTracker.clearDirtyFlag;
export const clearAllTradeDirtyFlags = tradeDirtyTracker.clearAll;

export const getTradeLastSyncTime = tradeSyncTimestamp.get;
export const setTradeLastSyncTime = tradeSyncTimestamp.set;
export const clearTradeLastSyncTime = tradeSyncTimestamp.clear;

// ============ Full sync tracking ============

const fullSyncTimestamp = createSyncTimestamp("tofustash_last_full_sync");

/**
 * Check if a full sync is needed (more than 24 hours since last full sync).
 * If needed, clears lastSyncTime to force a full pull.
 * Returns true if a full sync will be performed.
 */
export async function checkAndPrepareFullSyncIfNeeded(): Promise<boolean> {
  const lastFullSync = await fullSyncTimestamp.get();
  const now = Date.now();

  if (!lastFullSync) {
    await taskSyncTimestamp.clear();
    return true;
  }

  const lastFullSyncTime = parseInt(lastFullSync, 10);
  if (now - lastFullSyncTime > FULL_SYNC_INTERVAL_MS) {
    console.log("[Sync] Triggering periodic full sync (last was >24h ago)");
    await taskSyncTimestamp.clear();
    return true;
  }

  return false;
}

/**
 * Record that a full sync was completed.
 */
export async function recordFullSyncCompleted(): Promise<void> {
  await fullSyncTimestamp.set(Date.now().toString());
}

/**
 * Clear the full sync timestamp, forcing the next sync to be a full sync.
 */
export const clearFullSyncTimestamp = fullSyncTimestamp.clear;
