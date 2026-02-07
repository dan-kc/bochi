import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import type { HabitTag } from "../habitTag";
import { habitTagKey, parseHabitTagKey } from "../habitTag";
import { markHabitTagDirty, markHabitTagsDirty } from "../sync/syncStorage";

const HABIT_TAGS_STORAGE_KEY = "tofustash_habit_tags";

// ============ HabitTag Normalization ============

export function normalizeHabitTag(ht: Partial<HabitTag>): HabitTag {
  return {
    habit_id: ht.habit_id ?? "",
    tag_id: ht.tag_id ?? "",
    user_id: ht.user_id ?? "",
    created_at: ht.created_at ?? new Date().toISOString(),
    updated_at: ht.updated_at ?? new Date().toISOString(),
    deleted_at: ht.deleted_at ?? null,
  };
}

// ============ HabitTag Store State ============

interface HabitTagState {
  byKey: Record<string, HabitTag>;
  allKeys: string[];
}

type Listener = () => void;

// ============ HabitTag Store Class ============

class HabitTagStore {
  private state: HabitTagState = { byKey: {}, allKeys: [] };
  private listeners = new Set<Listener>();
  private initialized = false;

  constructor() {
    if (Platform.OS === "web" && typeof window !== "undefined") {
      this.state = this.readStorageSync();
      this.initialized = true;
      this.setupCrossTabSync();
      this.setupVisibilityReload();
    } else if (Platform.OS !== "web") {
      this.init();
      this.setupAppStateReload();
    }
  }

  private async init() {
    this.state = await this.readStorageAsync();
    this.initialized = true;
    this.notify();
  }

  // ============ Storage Helpers ============

  private readStorageSync(): HabitTagState {
    if (Platform.OS === "web" && typeof window !== "undefined") {
      const data = localStorage.getItem(HABIT_TAGS_STORAGE_KEY);
      const rawItems: Partial<HabitTag>[] = data ? JSON.parse(data) : [];
      return this.normalizeState(rawItems.map(normalizeHabitTag));
    }
    return { byKey: {}, allKeys: [] };
  }

  private async readStorageAsync(): Promise<HabitTagState> {
    if (Platform.OS === "web" && typeof window !== "undefined") {
      const data = localStorage.getItem(HABIT_TAGS_STORAGE_KEY);
      const rawItems: Partial<HabitTag>[] = data ? JSON.parse(data) : [];
      return this.normalizeState(rawItems.map(normalizeHabitTag));
    } else {
      const data = await AsyncStorage.getItem(HABIT_TAGS_STORAGE_KEY);
      const rawItems: Partial<HabitTag>[] = data ? JSON.parse(data) : [];
      return this.normalizeState(rawItems.map(normalizeHabitTag));
    }
  }

  private async writeStorage(): Promise<void> {
    const items = this.state.allKeys.map((key) => this.state.byKey[key]);
    const data = JSON.stringify(items);
    if (Platform.OS === "web" && typeof window !== "undefined") {
      localStorage.setItem(HABIT_TAGS_STORAGE_KEY, data);
    } else {
      await AsyncStorage.setItem(HABIT_TAGS_STORAGE_KEY, data);
    }
  }

  private normalizeState(items: HabitTag[]): HabitTagState {
    const byKey: Record<string, HabitTag> = {};
    const allKeys: string[] = [];
    for (const item of items) {
      const key = habitTagKey(item.habit_id, item.tag_id);
      byKey[key] = item;
      allKeys.push(key);
    }
    return { byKey, allKeys };
  }

  private setupCrossTabSync() {
    if (Platform.OS !== "web" || typeof window === "undefined") return;

    window.addEventListener("storage", (e) => {
      if (e.key === HABIT_TAGS_STORAGE_KEY && e.newValue) {
        const rawItems: Partial<HabitTag>[] = JSON.parse(e.newValue);
        this.state = this.normalizeState(rawItems.map(normalizeHabitTag));
        this.notify();
      }
    });
  }

  private setupVisibilityReload() {
    if (Platform.OS !== "web" || typeof window === "undefined") return;

    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") {
        this.state = this.readStorageSync();
        this.notify();
      }
    });
  }

  private setupAppStateReload() {
    import("react-native")
      .then(({ AppState }) => {
        AppState.addEventListener("change", (nextAppState) => {
          if (nextAppState === "active") {
            this.readStorageAsync().then((state) => {
              this.state = state;
              this.notify();
            });
          }
        });
      })
      .catch(() => {
        // AppState not available
      });
  }

  private notify() {
    for (const listener of this.listeners) {
      listener();
    }
  }

  // ============ useSyncExternalStore API ============

  subscribe = (listener: Listener): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): HabitTagState => this.state;
  getServerSnapshot = (): HabitTagState => this.state;

  // ============ Selectors ============

  getTagIdsForHabit(habitId: string): string[] {
    return this.state.allKeys
      .map((key) => this.state.byKey[key])
      .filter((ht) => ht.habit_id === habitId && !ht.deleted_at)
      .map((ht) => ht.tag_id);
  }

  getHabitIdsForTag(tagId: string): string[] {
    return this.state.allKeys
      .map((key) => this.state.byKey[key])
      .filter((ht) => ht.tag_id === tagId && !ht.deleted_at)
      .map((ht) => ht.habit_id);
  }

  getAll(userId: string): HabitTag[] {
    return this.state.allKeys
      .map((key) => this.state.byKey[key])
      .filter((ht) => ht.user_id === userId && !ht.deleted_at);
  }

  // ============ Mutations ============

  async addTagToHabit(userId: string, habitId: string, tagId: string): Promise<HabitTag> {
    const key = habitTagKey(habitId, tagId);
    const existing = this.state.byKey[key];

    // If exists and not deleted, return existing
    if (existing && !existing.deleted_at) {
      return existing;
    }

    const now = new Date().toISOString();
    const habitTag: HabitTag = {
      habit_id: habitId,
      tag_id: tagId,
      user_id: userId,
      created_at: existing?.created_at ?? now,
      updated_at: now,
      deleted_at: null,
    };

    this.state = {
      byKey: { ...this.state.byKey, [key]: habitTag },
      allKeys: existing ? this.state.allKeys : [key, ...this.state.allKeys],
    };

    await this.writeStorage();
    await markHabitTagDirty(key);
    this.notify();
    return habitTag;
  }

  async removeTagFromHabit(habitId: string, tagId: string): Promise<boolean> {
    const key = habitTagKey(habitId, tagId);
    const existing = this.state.byKey[key];
    if (!existing) return false;

    const now = new Date().toISOString();
    const updated = { ...existing, deleted_at: now, updated_at: now };
    this.state = {
      ...this.state,
      byKey: { ...this.state.byKey, [key]: updated },
    };

    await this.writeStorage();
    await markHabitTagDirty(key);
    this.notify();
    return true;
  }

  // ============ Sync Helpers ============

  async merge(serverHabitTags: Partial<HabitTag>[], userId?: string): Promise<void> {
    const newByKey = { ...this.state.byKey };
    const existingKeys = new Set(this.state.allKeys);

    for (const rawHt of serverHabitTags) {
      const ht = normalizeHabitTag(rawHt);
      const key = habitTagKey(ht.habit_id, ht.tag_id);
      const existing = newByKey[key];
      const user_id = existing?.user_id || userId || ht.user_id;
      newByKey[key] = { ...ht, user_id };
      if (!existingKeys.has(key)) {
        existingKeys.add(key);
      }
    }

    this.state = {
      byKey: newByKey,
      allKeys: Array.from(existingKeys),
    };

    await this.writeStorage();
    this.notify();
  }

  getDirty(dirtyKeys: Set<string>): HabitTag[] {
    return Array.from(dirtyKeys)
      .map((key) => this.state.byKey[key])
      .filter(Boolean);
  }

  async updateAllUserId(newUserId: string, fromUserId?: string): Promise<string[]> {
    const keys: string[] = [];
    const newByKey: Record<string, HabitTag> = {};

    for (const key of this.state.allKeys) {
      const item = this.state.byKey[key];
      if (fromUserId && item.user_id !== fromUserId) {
        newByKey[key] = item;
        continue;
      }
      newByKey[key] = { ...item, user_id: newUserId };
      keys.push(key);
    }

    this.state = {
      byKey: newByKey,
      allKeys: this.state.allKeys,
    };

    await this.writeStorage();

    if (keys.length > 0) {
      await markHabitTagsDirty(keys);
    }

    this.notify();
    return keys;
  }

  async purgeDeleted(): Promise<void> {
    const activeKeys = this.state.allKeys.filter(
      (key) => this.state.byKey[key].deleted_at === null,
    );
    const activeByKey: Record<string, HabitTag> = {};
    for (const key of activeKeys) {
      activeByKey[key] = this.state.byKey[key];
    }

    this.state = { byKey: activeByKey, allKeys: activeKeys };
    await this.writeStorage();
    this.notify();
  }

  async clearAll(): Promise<void> {
    this.state = { byKey: {}, allKeys: [] };
    await this.writeStorage();
    this.notify();
  }

  async reload(): Promise<void> {
    this.state = await this.readStorageAsync();
    this.notify();
  }
}

export const habitTagStore = new HabitTagStore();
