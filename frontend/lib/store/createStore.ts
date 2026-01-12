import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";

// ============ Types ============

export interface EntityState<T> {
  byId: Record<string, T>;
  allIds: string[];
}

export interface BaseEntity {
  id: string;
  user_id: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

type Listener = () => void;

export interface StoreConfig<T extends BaseEntity> {
  storageKey: string;
  normalize: (raw: Partial<T>) => T;
  markDirty: (id: string) => Promise<void>;
  markManyDirty: (ids: string[]) => Promise<void>;
  enableVisibilityReload?: boolean;
  enableAppStateReload?: boolean;
}

// ============ Generic Store Class ============

export class EntityStore<T extends BaseEntity> {
  protected state: EntityState<T> = { byId: {}, allIds: [] };
  protected listeners = new Set<Listener>();
  protected initialized = false;
  protected config: StoreConfig<T>;

  constructor(config: StoreConfig<T>) {
    this.config = config;

    if (Platform.OS === "web" && typeof window !== "undefined") {
      this.state = this.readStorageSync();
      this.initialized = true;
      this.setupCrossTabSync();
      if (config.enableVisibilityReload) {
        this.setupVisibilityReload();
      }
    } else if (Platform.OS !== "web") {
      this.init();
      if (config.enableAppStateReload) {
        this.setupAppStateReload();
      }
    }
  }

  private async init() {
    this.state = await this.readStorageAsync();
    this.initialized = true;
    this.notify();
  }

  // ============ Storage Helpers ============

  protected readStorageSync(): EntityState<T> {
    if (Platform.OS === "web" && typeof window !== "undefined") {
      const data = localStorage.getItem(this.config.storageKey);
      const rawItems: Partial<T>[] = data ? JSON.parse(data) : [];
      const items = rawItems.map(this.config.normalize);

      // Persist normalized data back (migrates old schema to current)
      localStorage.setItem(this.config.storageKey, JSON.stringify(items));

      return this.normalizeState(items);
    }
    return { byId: {}, allIds: [] };
  }

  protected async readStorageAsync(): Promise<EntityState<T>> {
    if (Platform.OS === "web" && typeof window !== "undefined") {
      const data = localStorage.getItem(this.config.storageKey);
      const rawItems: Partial<T>[] = data ? JSON.parse(data) : [];
      const items = rawItems.map(this.config.normalize);

      // Persist normalized data back (migrates old schema to current)
      localStorage.setItem(this.config.storageKey, JSON.stringify(items));

      return this.normalizeState(items);
    } else {
      const data = await AsyncStorage.getItem(this.config.storageKey);
      const rawItems: Partial<T>[] = data ? JSON.parse(data) : [];
      const items = rawItems.map(this.config.normalize);

      // Persist normalized data back (migrates old schema to current)
      await AsyncStorage.setItem(this.config.storageKey, JSON.stringify(items));

      return this.normalizeState(items);
    }
  }

  protected async writeStorage(): Promise<void> {
    const items = this.denormalizeState();
    const data = JSON.stringify(items);
    if (Platform.OS === "web" && typeof window !== "undefined") {
      localStorage.setItem(this.config.storageKey, data);
    } else {
      await AsyncStorage.setItem(this.config.storageKey, data);
    }
  }

  protected normalizeState(items: T[]): EntityState<T> {
    const byId: Record<string, T> = {};
    const allIds: string[] = [];
    for (const item of items) {
      byId[item.id] = item;
      allIds.push(item.id);
    }
    return { byId, allIds };
  }

  protected denormalizeState(): T[] {
    return this.state.allIds.map((id) => this.state.byId[id]);
  }

  protected verifyStorageConsistency(): boolean {
    if (Platform.OS !== "web" || typeof window === "undefined") return true;
    const stored = localStorage.getItem(this.config.storageKey);
    const memoryData = JSON.stringify(this.denormalizeState());
    return stored === memoryData;
  }

  // ============ Cross-tab and lifecycle sync ============

  private setupCrossTabSync() {
    if (Platform.OS !== "web" || typeof window === "undefined") return;

    window.addEventListener("storage", (e) => {
      if (e.key === this.config.storageKey && e.newValue) {
        const rawItems: Partial<T>[] = JSON.parse(e.newValue);
        const items = rawItems.map(this.config.normalize);
        this.state = this.normalizeState(items);
        this.notify();
      }
    });
  }

  private setupVisibilityReload() {
    if (Platform.OS !== "web" || typeof window === "undefined") return;

    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") {
        if (!this.verifyStorageConsistency()) {
          console.log(`[${this.config.storageKey}] State mismatch detected on visibility change, reloading from storage`);
          this.state = this.readStorageSync();
          this.notify();
        }
      }
    });
  }

  private setupAppStateReload() {
    import("react-native")
      .then(({ AppState }) => {
        AppState.addEventListener("change", (nextAppState) => {
          if (nextAppState === "active") {
            this.readStorageAsync().then((state) => {
              const currentIds = this.state.allIds.join(",");
              const newIds = state.allIds.join(",");
              if (currentIds !== newIds) {
                console.log(`[${this.config.storageKey}] State change detected on app foreground, reloading`);
                this.state = state;
                this.notify();
              }
            });
          }
        });
      })
      .catch(() => {
        // AppState not available (SSR or test environment)
      });
  }

  protected notify() {
    for (const listener of this.listeners) {
      listener();
    }
  }

  // ============ useSyncExternalStore API ============

  subscribe = (listener: Listener): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): EntityState<T> => {
    return this.state;
  };

  getServerSnapshot = (): EntityState<T> => {
    return this.state;
  };

  // ============ Common Selectors ============

  getAll(userId: string): T[] {
    return this.state.allIds
      .map((id) => this.state.byId[id])
      .filter((t) => t.user_id === userId && !t.deleted_at)
      .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
  }

  getById(id: string): T | undefined {
    return this.state.byId[id];
  }

  // ============ Sync Helpers ============

  async merge(serverItems: Partial<T>[], userId?: string): Promise<void> {
    const newById = { ...this.state.byId };
    const existingIds = new Set(this.state.allIds);

    for (const rawItem of serverItems) {
      const item = this.config.normalize(rawItem);
      const existing = newById[item.id];
      const user_id = existing?.user_id || userId || item.user_id;
      newById[item.id] = { ...item, user_id };
      if (!existingIds.has(item.id)) {
        existingIds.add(item.id);
      }
    }

    this.state = {
      byId: newById,
      allIds: Array.from(existingIds),
    };

    await this.writeStorage();
    this.notify();
  }

  getDirty(dirtyIds: Set<string>): T[] {
    return Array.from(dirtyIds)
      .map((id) => this.state.byId[id])
      .filter(Boolean);
  }

  async reload(): Promise<void> {
    this.state = await this.readStorageAsync();
    this.notify();
  }

  async clearAll(): Promise<void> {
    this.state = { byId: {}, allIds: [] };
    await this.writeStorage();
    this.notify();
  }

  async updateAllUserId(newUserId: string, fromUserId?: string): Promise<string[]> {
    const itemIds: string[] = [];
    const newById: Record<string, T> = {};

    for (const id of this.state.allIds) {
      const item = this.state.byId[id];
      if (fromUserId && item.user_id !== fromUserId) {
        newById[id] = item;
        continue;
      }
      newById[id] = { ...item, user_id: newUserId };
      itemIds.push(id);
    }

    this.state = {
      byId: newById,
      allIds: this.state.allIds,
    };

    await this.writeStorage();

    if (itemIds.length > 0) {
      await this.config.markManyDirty(itemIds);
    }

    this.notify();
    return itemIds;
  }

  async purgeDeleted(): Promise<void> {
    const activeIds = this.state.allIds.filter(
      (id) => this.state.byId[id].deleted_at === null,
    );
    const activeById: Record<string, T> = {};
    for (const id of activeIds) {
      activeById[id] = this.state.byId[id];
    }

    this.state = { byId: activeById, allIds: activeIds };
    await this.writeStorage();
    this.notify();
  }

  // ============ Protected mutation helpers ============

  protected async addItem(item: T): Promise<void> {
    this.state = {
      byId: { ...this.state.byId, [item.id]: item },
      allIds: [item.id, ...this.state.allIds],
    };
    await this.writeStorage();
    await this.config.markDirty(item.id);
    this.notify();
  }

  protected async updateItem(id: string, updates: Partial<T>): Promise<T | null> {
    const existing = this.state.byId[id];
    if (!existing) return null;

    const updated = { ...existing, ...updates, updated_at: new Date().toISOString() };
    this.state = {
      ...this.state,
      byId: { ...this.state.byId, [id]: updated },
    };

    await this.writeStorage();
    await this.config.markDirty(id);
    this.notify();
    return updated;
  }
}

// ============ Utilities ============

export function generateUUID(): string {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}
