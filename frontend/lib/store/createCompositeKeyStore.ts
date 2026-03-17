import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";

// ============ Types ============

interface CompositeKeyState<T> {
  byKey: Record<string, T>;
  allKeys: string[];
}

type Listener = () => void;

interface CompositeKeyEntity {
  user_id: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface CompositeKeyStoreConfig<T extends CompositeKeyEntity> {
  storageKey: string;
  normalize: (raw: Partial<T>) => T;
  getKey: (item: T) => string;
  markDirty: (key: string) => Promise<void>;
  markManyDirty: (keys: string[]) => Promise<void>;
}

// ============ CompositeKeyStore Class ============

export class CompositeKeyStore<T extends CompositeKeyEntity> {
  private state: CompositeKeyState<T> = { byKey: {}, allKeys: [] };
  private listeners = new Set<Listener>();
  private initialized = false;
  private config: CompositeKeyStoreConfig<T>;

  constructor(config: CompositeKeyStoreConfig<T>) {
    this.config = config;

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

  private readStorageSync(): CompositeKeyState<T> {
    if (Platform.OS === "web" && typeof window !== "undefined") {
      const data = localStorage.getItem(this.config.storageKey);
      const rawItems: Partial<T>[] = data ? JSON.parse(data) : [];
      return this.normalizeState(rawItems.map(this.config.normalize));
    }
    return { byKey: {}, allKeys: [] };
  }

  private async readStorageAsync(): Promise<CompositeKeyState<T>> {
    if (Platform.OS === "web" && typeof window !== "undefined") {
      const data = localStorage.getItem(this.config.storageKey);
      const rawItems: Partial<T>[] = data ? JSON.parse(data) : [];
      return this.normalizeState(rawItems.map(this.config.normalize));
    } else {
      const data = await AsyncStorage.getItem(this.config.storageKey);
      const rawItems: Partial<T>[] = data ? JSON.parse(data) : [];
      return this.normalizeState(rawItems.map(this.config.normalize));
    }
  }

  private async writeStorage(): Promise<void> {
    const items = this.state.allKeys.map((key) => this.state.byKey[key]);
    const data = JSON.stringify(items);
    if (Platform.OS === "web" && typeof window !== "undefined") {
      localStorage.setItem(this.config.storageKey, data);
    } else {
      await AsyncStorage.setItem(this.config.storageKey, data);
    }
  }

  private normalizeState(items: T[]): CompositeKeyState<T> {
    const byKey: Record<string, T> = {};
    const allKeys: string[] = [];
    for (const item of items) {
      const key = this.config.getKey(item);
      byKey[key] = item;
      allKeys.push(key);
    }
    return { byKey, allKeys };
  }

  // ============ Cross-tab and lifecycle sync ============

  private setupCrossTabSync() {
    if (Platform.OS !== "web" || typeof window === "undefined") return;

    window.addEventListener("storage", (e) => {
      if (e.key === this.config.storageKey && e.newValue) {
        const rawItems: Partial<T>[] = JSON.parse(e.newValue);
        this.state = this.normalizeState(rawItems.map(this.config.normalize));
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

  getSnapshot = (): CompositeKeyState<T> => this.state;
  getServerSnapshot = (): CompositeKeyState<T> => this.state;

  // ============ Selectors ============

  getIdsForField<K extends keyof T>(
    filterField: K,
    filterValue: T[K],
    returnField: keyof T,
  ): string[] {
    return this.state.allKeys
      .map((key) => this.state.byKey[key])
      .filter((item) => item[filterField] === filterValue && !item.deleted_at)
      .map((item) => item[returnField] as string);
  }

  getAll(userId: string): T[] {
    return this.state.allKeys
      .map((key) => this.state.byKey[key])
      .filter((item) => item.user_id === userId && !item.deleted_at);
  }

  // ============ Mutations ============

  async addItem(item: T): Promise<T> {
    const key = this.config.getKey(item);
    const existing = this.state.byKey[key];

    // If exists and not deleted, return existing
    if (existing && !existing.deleted_at) {
      return existing;
    }

    const finalItem = existing
      ? { ...item, created_at: existing.created_at }
      : item;

    this.state = {
      byKey: { ...this.state.byKey, [key]: finalItem },
      allKeys: existing ? this.state.allKeys : [key, ...this.state.allKeys],
    };

    await this.writeStorage();
    await this.config.markDirty(key);
    this.notify();
    return finalItem;
  }

  async removeItem(key: string, item: T): Promise<boolean> {
    const existing = this.state.byKey[key];
    if (!existing) return false;

    const now = new Date().toISOString();
    const updated = { ...existing, deleted_at: now, updated_at: now } as T;
    this.state = {
      ...this.state,
      byKey: { ...this.state.byKey, [key]: updated },
    };

    await this.writeStorage();
    await this.config.markDirty(key);
    this.notify();
    return true;
  }

  // ============ Sync Helpers ============

  async merge(serverItems: Partial<T>[], userId?: string): Promise<void> {
    const newByKey = { ...this.state.byKey };
    const existingKeys = new Set(this.state.allKeys);

    for (const rawItem of serverItems) {
      const item = this.config.normalize(rawItem);
      const key = this.config.getKey(item);
      const existing = newByKey[key];
      const user_id = existing?.user_id || userId || item.user_id;
      newByKey[key] = { ...item, user_id } as T;
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

  getDirty(dirtyKeys: Set<string>): T[] {
    return Array.from(dirtyKeys)
      .map((key) => this.state.byKey[key])
      .filter(Boolean);
  }

  async updateAllUserId(newUserId: string, fromUserId?: string): Promise<string[]> {
    const keys: string[] = [];
    const newByKey: Record<string, T> = {};

    for (const key of this.state.allKeys) {
      const item = this.state.byKey[key];
      if (fromUserId && item.user_id !== fromUserId) {
        newByKey[key] = item;
        continue;
      }
      newByKey[key] = { ...item, user_id: newUserId } as T;
      keys.push(key);
    }

    this.state = {
      byKey: newByKey,
      allKeys: this.state.allKeys,
    };

    await this.writeStorage();

    if (keys.length > 0) {
      await this.config.markManyDirty(keys);
    }

    this.notify();
    return keys;
  }

  async purgeDeleted(): Promise<void> {
    const activeKeys = this.state.allKeys.filter(
      (key) => this.state.byKey[key].deleted_at === null,
    );
    const activeByKey: Record<string, T> = {};
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
