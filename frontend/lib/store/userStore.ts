import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";

const USER_STORAGE_KEY = "tofustash_user";

// ============ Types ============

interface UserState {
  email: string | null;
  isPremium: boolean;
}

type Listener = () => void;

// ============ Storage Helpers ============

function readStorageSync(): UserState {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    const data = localStorage.getItem(USER_STORAGE_KEY);
    if (data) {
      const parsed = JSON.parse(data);
      return {
        email: parsed.email ?? null,
        isPremium: parsed.isPremium ?? false,
      };
    }
  }
  return { email: null, isPremium: false };
}

async function readStorageAsync(): Promise<UserState> {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    return readStorageSync();
  } else {
    const data = await AsyncStorage.getItem(USER_STORAGE_KEY);
    if (data) {
      const parsed = JSON.parse(data);
      return {
        email: parsed.email ?? null,
        isPremium: parsed.isPremium ?? false,
      };
    }
    return { email: null, isPremium: false };
  }
}

async function writeStorage(state: UserState): Promise<void> {
  const data = JSON.stringify(state);
  if (Platform.OS === "web" && typeof window !== "undefined") {
    localStorage.setItem(USER_STORAGE_KEY, data);
  } else {
    await AsyncStorage.setItem(USER_STORAGE_KEY, data);
  }
}

// ============ Store Class ============

class UserStore {
  private state: UserState = { email: null, isPremium: false };
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
      if (e.key === USER_STORAGE_KEY && e.newValue) {
        const parsed = JSON.parse(e.newValue);
        this.state = {
          email: parsed.email ?? null,
          isPremium: parsed.isPremium ?? false,
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

  // ============ useSyncExternalStore API ============

  subscribe = (listener: Listener): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): UserState => {
    return this.state;
  };

  getServerSnapshot = (): UserState => {
    return this.state;
  };

  // ============ Selectors ============

  getEmail(): string | null {
    return this.state.email;
  }

  getIsPremium(): boolean {
    return this.state.isPremium;
  }

  // ============ Mutations ============

  async setUser(email: string | null, isPremium: boolean): Promise<void> {
    this.state = {
      email,
      isPremium,
    };
    await writeStorage(this.state);
    this.notify();
  }

  async reload(): Promise<void> {
    this.state = await readStorageAsync();
    this.notify();
  }

  async clear(): Promise<void> {
    this.state = { email: null, isPremium: false };
    await writeStorage(this.state);
    this.notify();
  }
}

// ============ Singleton Export ============

export const userStore = new UserStore();
