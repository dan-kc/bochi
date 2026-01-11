import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";

const BALANCE_STORAGE_KEY = "tofustash_balance";

// ============ Types ============

interface BalanceState {
  soy_balance: number;
  tofu_balance: number;
}

type Listener = () => void;

// ============ Storage Helpers ============

function readStorageSync(): BalanceState {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    const data = localStorage.getItem(BALANCE_STORAGE_KEY);
    if (data) {
      const parsed = JSON.parse(data);
      return {
        soy_balance: parsed.soy_balance ?? 0,
        tofu_balance: parsed.tofu_balance ?? 0,
      };
    }
  }
  return { soy_balance: 0, tofu_balance: 0 };
}

async function readStorageAsync(): Promise<BalanceState> {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    return readStorageSync();
  } else {
    const data = await AsyncStorage.getItem(BALANCE_STORAGE_KEY);
    if (data) {
      const parsed = JSON.parse(data);
      return {
        soy_balance: parsed.soy_balance ?? 0,
        tofu_balance: parsed.tofu_balance ?? 0,
      };
    }
    return { soy_balance: 0, tofu_balance: 0 };
  }
}

async function writeStorage(state: BalanceState): Promise<void> {
  const data = JSON.stringify(state);
  if (Platform.OS === "web" && typeof window !== "undefined") {
    localStorage.setItem(BALANCE_STORAGE_KEY, data);
  } else {
    await AsyncStorage.setItem(BALANCE_STORAGE_KEY, data);
  }
}

// ============ Store Class ============

class BalanceStore {
  private state: BalanceState = { soy_balance: 0, tofu_balance: 0 };
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
      if (e.key === BALANCE_STORAGE_KEY && e.newValue) {
        const parsed = JSON.parse(e.newValue);
        this.state = {
          soy_balance: parsed.soy_balance ?? 0,
          tofu_balance: parsed.tofu_balance ?? 0,
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

  getSnapshot = (): BalanceState => {
    return this.state;
  };

  getServerSnapshot = (): BalanceState => {
    return this.state;
  };

  // ============ Selectors ============

  getSoyBalance(): number {
    return this.state.soy_balance;
  }

  getTofuBalance(): number {
    return this.state.tofu_balance;
  }

  // ============ Mutations ============

  async addSoy(amount: number): Promise<void> {
    this.state = {
      ...this.state,
      soy_balance: this.state.soy_balance + amount,
    };
    await writeStorage(this.state);
    this.notify();
  }

  async setBalance(soy: number, tofu: number): Promise<void> {
    this.state = {
      soy_balance: soy,
      tofu_balance: tofu,
    };
    await writeStorage(this.state);
    this.notify();
  }

  async setSoyBalance(soy: number): Promise<void> {
    this.state = {
      ...this.state,
      soy_balance: soy,
    };
    await writeStorage(this.state);
    this.notify();
  }

  async reload(): Promise<void> {
    this.state = await readStorageAsync();
    this.notify();
  }

  async clear(): Promise<void> {
    this.state = { soy_balance: 0, tofu_balance: 0 };
    await writeStorage(this.state);
    this.notify();
  }
}

// ============ Singleton Export ============

export const balanceStore = new BalanceStore();
