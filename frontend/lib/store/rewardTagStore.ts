import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import type { RewardTag } from "../rewardTag";
import { rewardTagKey, parseRewardTagKey } from "../rewardTag";
import { markRewardTagDirty, markRewardTagsDirty } from "../sync/syncStorage";

const REWARD_TAGS_STORAGE_KEY = "tofustash_reward_tags";

// ============ RewardTag Normalization ============

export function normalizeRewardTag(rt: Partial<RewardTag>): RewardTag {
  return {
    reward_id: rt.reward_id ?? "",
    tag_id: rt.tag_id ?? "",
    user_id: rt.user_id ?? "",
    created_at: rt.created_at ?? new Date().toISOString(),
    updated_at: rt.updated_at ?? new Date().toISOString(),
    deleted_at: rt.deleted_at ?? null,
  };
}

// ============ RewardTag Store State ============

interface RewardTagState {
  byKey: Record<string, RewardTag>;
  allKeys: string[];
}

type Listener = () => void;

// ============ RewardTag Store Class ============

class RewardTagStore {
  private state: RewardTagState = { byKey: {}, allKeys: [] };
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

  private readStorageSync(): RewardTagState {
    if (Platform.OS === "web" && typeof window !== "undefined") {
      const data = localStorage.getItem(REWARD_TAGS_STORAGE_KEY);
      const rawItems: Partial<RewardTag>[] = data ? JSON.parse(data) : [];
      return this.normalizeState(rawItems.map(normalizeRewardTag));
    }
    return { byKey: {}, allKeys: [] };
  }

  private async readStorageAsync(): Promise<RewardTagState> {
    if (Platform.OS === "web" && typeof window !== "undefined") {
      const data = localStorage.getItem(REWARD_TAGS_STORAGE_KEY);
      const rawItems: Partial<RewardTag>[] = data ? JSON.parse(data) : [];
      return this.normalizeState(rawItems.map(normalizeRewardTag));
    } else {
      const data = await AsyncStorage.getItem(REWARD_TAGS_STORAGE_KEY);
      const rawItems: Partial<RewardTag>[] = data ? JSON.parse(data) : [];
      return this.normalizeState(rawItems.map(normalizeRewardTag));
    }
  }

  private async writeStorage(): Promise<void> {
    const items = this.state.allKeys.map((key) => this.state.byKey[key]);
    const data = JSON.stringify(items);
    if (Platform.OS === "web" && typeof window !== "undefined") {
      localStorage.setItem(REWARD_TAGS_STORAGE_KEY, data);
    } else {
      await AsyncStorage.setItem(REWARD_TAGS_STORAGE_KEY, data);
    }
  }

  private normalizeState(items: RewardTag[]): RewardTagState {
    const byKey: Record<string, RewardTag> = {};
    const allKeys: string[] = [];
    for (const item of items) {
      const key = rewardTagKey(item.reward_id, item.tag_id);
      byKey[key] = item;
      allKeys.push(key);
    }
    return { byKey, allKeys };
  }

  private setupCrossTabSync() {
    if (Platform.OS !== "web" || typeof window === "undefined") return;

    window.addEventListener("storage", (e) => {
      if (e.key === REWARD_TAGS_STORAGE_KEY && e.newValue) {
        const rawItems: Partial<RewardTag>[] = JSON.parse(e.newValue);
        this.state = this.normalizeState(rawItems.map(normalizeRewardTag));
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

  getSnapshot = (): RewardTagState => this.state;
  getServerSnapshot = (): RewardTagState => this.state;

  // ============ Selectors ============

  getTagIdsForReward(rewardId: string): string[] {
    return this.state.allKeys
      .map((key) => this.state.byKey[key])
      .filter((rt) => rt.reward_id === rewardId && !rt.deleted_at)
      .map((rt) => rt.tag_id);
  }

  getRewardIdsForTag(tagId: string): string[] {
    return this.state.allKeys
      .map((key) => this.state.byKey[key])
      .filter((rt) => rt.tag_id === tagId && !rt.deleted_at)
      .map((rt) => rt.reward_id);
  }

  getAll(userId: string): RewardTag[] {
    return this.state.allKeys
      .map((key) => this.state.byKey[key])
      .filter((rt) => rt.user_id === userId && !rt.deleted_at);
  }

  // ============ Mutations ============

  async addTagToReward(userId: string, rewardId: string, tagId: string): Promise<RewardTag> {
    const key = rewardTagKey(rewardId, tagId);
    const existing = this.state.byKey[key];

    // If exists and not deleted, return existing
    if (existing && !existing.deleted_at) {
      return existing;
    }

    const now = new Date().toISOString();
    const rewardTag: RewardTag = {
      reward_id: rewardId,
      tag_id: tagId,
      user_id: userId,
      created_at: existing?.created_at ?? now,
      updated_at: now,
      deleted_at: null,
    };

    this.state = {
      byKey: { ...this.state.byKey, [key]: rewardTag },
      allKeys: existing ? this.state.allKeys : [key, ...this.state.allKeys],
    };

    await this.writeStorage();
    await markRewardTagDirty(key);
    this.notify();
    return rewardTag;
  }

  async removeTagFromReward(rewardId: string, tagId: string): Promise<boolean> {
    const key = rewardTagKey(rewardId, tagId);
    const existing = this.state.byKey[key];
    if (!existing) return false;

    const now = new Date().toISOString();
    const updated = { ...existing, deleted_at: now, updated_at: now };
    this.state = {
      ...this.state,
      byKey: { ...this.state.byKey, [key]: updated },
    };

    await this.writeStorage();
    await markRewardTagDirty(key);
    this.notify();
    return true;
  }

  // ============ Sync Helpers ============

  async merge(serverRewardTags: Partial<RewardTag>[], userId?: string): Promise<void> {
    const newByKey = { ...this.state.byKey };
    const existingKeys = new Set(this.state.allKeys);

    for (const rawRt of serverRewardTags) {
      const rt = normalizeRewardTag(rawRt);
      const key = rewardTagKey(rt.reward_id, rt.tag_id);
      const existing = newByKey[key];
      const user_id = existing?.user_id || userId || rt.user_id;
      newByKey[key] = { ...rt, user_id };
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

  getDirty(dirtyKeys: Set<string>): RewardTag[] {
    return Array.from(dirtyKeys)
      .map((key) => this.state.byKey[key])
      .filter(Boolean);
  }

  async updateAllUserId(newUserId: string, fromUserId?: string): Promise<string[]> {
    const keys: string[] = [];
    const newByKey: Record<string, RewardTag> = {};

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
      await markRewardTagsDirty(keys);
    }

    this.notify();
    return keys;
  }

  async purgeDeleted(): Promise<void> {
    const activeKeys = this.state.allKeys.filter(
      (key) => this.state.byKey[key].deleted_at === null,
    );
    const activeByKey: Record<string, RewardTag> = {};
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

export const rewardTagStore = new RewardTagStore();
