import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { useSyncExternalStore, useCallback } from "react";
import { type SortKey, DEFAULT_SORT } from "../sortOptions";

const STORAGE_KEY = "tofustash_sort_habit";

type Listener = () => void;

function readStorageSync(): SortKey {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    return (localStorage.getItem(STORAGE_KEY) as SortKey) || DEFAULT_SORT;
  }
  return DEFAULT_SORT;
}

async function readStorageAsync(): Promise<SortKey> {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    return readStorageSync();
  } else {
    const value = await AsyncStorage.getItem(STORAGE_KEY);
    return (value as SortKey) || DEFAULT_SORT;
  }
}

async function writeStorage(sortKey: SortKey): Promise<void> {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    localStorage.setItem(STORAGE_KEY, sortKey);
  } else {
    await AsyncStorage.setItem(STORAGE_KEY, sortKey);
  }
}

class SortPreferencesStore {
  private state: SortKey = DEFAULT_SORT;
  private listeners = new Set<Listener>();
  private initialized = false;

  constructor() {
    if (Platform.OS === "web" && typeof window !== "undefined") {
      this.state = readStorageSync();
      this.initialized = true;
      this.setupCrossTabSync();
    } else if (Platform.OS !== "web") {
      this.init();
    }
  }

  private async init() {
    this.state = await readStorageAsync();
    this.initialized = true;
    this.notify();
  }

  private setupCrossTabSync() {
    if (Platform.OS !== "web" || typeof window === "undefined") return;

    window.addEventListener("storage", (e) => {
      if (e.key === STORAGE_KEY && e.newValue) {
        this.state = e.newValue as SortKey;
        this.notify();
      }
    });
  }

  private notify() {
    for (const listener of this.listeners) {
      listener();
    }
  }

  subscribe = (listener: Listener): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): SortKey => {
    return this.state;
  };

  getServerSnapshot = (): SortKey => {
    return this.state;
  };

  getSort(): SortKey {
    return this.state;
  }

  async setSort(sortKey: SortKey): Promise<void> {
    this.state = sortKey;
    await writeStorage(sortKey);
    this.notify();
  }

  async reload(): Promise<void> {
    this.state = await readStorageAsync();
    this.notify();
  }
}

export const sortPreferencesStore = new SortPreferencesStore();

export function useSortPreference(): [SortKey, (sortKey: SortKey) => void] {
  const sortKey = useSyncExternalStore(
    sortPreferencesStore.subscribe,
    sortPreferencesStore.getSnapshot,
    sortPreferencesStore.getServerSnapshot
  );

  const setSortKey = useCallback((newSortKey: SortKey) => {
    sortPreferencesStore.setSort(newSortKey);
  }, []);

  return [sortKey, setSortKey];
}
