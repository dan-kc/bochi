import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { useSyncExternalStore, useCallback } from "react";
import {
  type TabType,
  type SortKey,
  DEFAULT_SORT,
  isValidSortForTab,
} from "../sortOptions";

const STORAGE_KEYS: Record<TabType, string> = {
  both: "tofustash_sort_both",
  habit: "tofustash_sort_habit",
  todo: "tofustash_sort_todo",
};

type Listener = () => void;

interface SortPreferencesState {
  both: SortKey;
  habit: SortKey;
  todo: SortKey;
}

function readStorageSync(): SortPreferencesState {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    return {
      both:
        (localStorage.getItem(STORAGE_KEYS.both) as SortKey) ||
        DEFAULT_SORT.both,
      habit:
        (localStorage.getItem(STORAGE_KEYS.habit) as SortKey) ||
        DEFAULT_SORT.habit,
      todo:
        (localStorage.getItem(STORAGE_KEYS.todo) as SortKey) ||
        DEFAULT_SORT.todo,
    };
  }
  return { ...DEFAULT_SORT };
}

async function readStorageAsync(): Promise<SortPreferencesState> {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    return readStorageSync();
  } else {
    const [both, habit, todo] = await Promise.all([
      AsyncStorage.getItem(STORAGE_KEYS.both),
      AsyncStorage.getItem(STORAGE_KEYS.habit),
      AsyncStorage.getItem(STORAGE_KEYS.todo),
    ]);
    return {
      both: (both as SortKey) || DEFAULT_SORT.both,
      habit: (habit as SortKey) || DEFAULT_SORT.habit,
      todo: (todo as SortKey) || DEFAULT_SORT.todo,
    };
  }
}

async function writeStorage(tab: TabType, sortKey: SortKey): Promise<void> {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    localStorage.setItem(STORAGE_KEYS[tab], sortKey);
  } else {
    await AsyncStorage.setItem(STORAGE_KEYS[tab], sortKey);
  }
}

class SortPreferencesStore {
  private state: SortPreferencesState = { ...DEFAULT_SORT };
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
      const tab = (Object.keys(STORAGE_KEYS) as TabType[]).find(
        (t) => STORAGE_KEYS[t] === e.key
      );
      if (tab && e.newValue) {
        this.state = {
          ...this.state,
          [tab]: e.newValue as SortKey,
        };
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

  getSnapshot = (): SortPreferencesState => {
    return this.state;
  };

  getServerSnapshot = (): SortPreferencesState => {
    return this.state;
  };

  getSortForTab(tab: TabType): SortKey {
    const stored = this.state[tab];
    if (isValidSortForTab(tab, stored)) {
      return stored;
    }
    return DEFAULT_SORT[tab];
  }

  async setSortForTab(tab: TabType, sortKey: SortKey): Promise<void> {
    if (!isValidSortForTab(tab, sortKey)) {
      return;
    }
    this.state = {
      ...this.state,
      [tab]: sortKey,
    };
    await writeStorage(tab, sortKey);
    this.notify();
  }

  async reload(): Promise<void> {
    this.state = await readStorageAsync();
    this.notify();
  }
}

export const sortPreferencesStore = new SortPreferencesStore();

export function useSortPreference(
  tab: TabType
): [SortKey, (sortKey: SortKey) => void] {
  const state = useSyncExternalStore(
    sortPreferencesStore.subscribe,
    sortPreferencesStore.getSnapshot,
    sortPreferencesStore.getServerSnapshot
  );

  const sortKey = isValidSortForTab(tab, state[tab])
    ? state[tab]
    : DEFAULT_SORT[tab];

  const setSortKey = useCallback(
    (newSortKey: SortKey) => {
      sortPreferencesStore.setSortForTab(tab, newSortKey);
    },
    [tab]
  );

  return [sortKey, setSortKey];
}
