import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";

const DIRTY_TASKS_KEY = "tofustash_dirty_tasks";
const LAST_SYNC_KEY = "tofustash_last_sync";

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
