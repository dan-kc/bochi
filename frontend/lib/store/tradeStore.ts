import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import type { Trade, TradeInput } from "../trade";
import { markTradeDirty, markTradesDirty } from "../sync/syncStorage";

const TRADES_STORAGE_KEY = "tofustash_trades";

// ============ Types ============

interface TradeState {
  byId: Record<string, Trade>;
  allIds: string[];
}

type Listener = () => void;

// ============ Storage Helpers ============

/**
 * Normalize a trade from storage to ensure all fields exist.
 */
function normalizeTrade(trade: Partial<Trade>): Trade {
  return {
    id: trade.id ?? "",
    user_id: trade.user_id ?? "",
    task_id: trade.task_id ?? null,
    reward_id: trade.reward_id ?? null,
    amount: trade.amount ?? 0,
    created_at: trade.created_at ?? new Date().toISOString(),
    updated_at: trade.updated_at ?? new Date().toISOString(),
    deleted_at: trade.deleted_at ?? null,
  };
}

function readStorageSync(): TradeState {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    const data = localStorage.getItem(TRADES_STORAGE_KEY);
    const rawTrades: Partial<Trade>[] = data ? JSON.parse(data) : [];
    const trades = rawTrades.map(normalizeTrade);
    return normalize(trades);
  }
  return { byId: {}, allIds: [] };
}

async function readStorageAsync(): Promise<TradeState> {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    const data = localStorage.getItem(TRADES_STORAGE_KEY);
    const rawTrades: Partial<Trade>[] = data ? JSON.parse(data) : [];
    const trades = rawTrades.map(normalizeTrade);
    return normalize(trades);
  } else {
    const data = await AsyncStorage.getItem(TRADES_STORAGE_KEY);
    const rawTrades: Partial<Trade>[] = data ? JSON.parse(data) : [];
    const trades = rawTrades.map(normalizeTrade);
    return normalize(trades);
  }
}

async function writeStorage(state: TradeState): Promise<void> {
  const trades = denormalize(state);
  const data = JSON.stringify(trades);
  if (Platform.OS === "web" && typeof window !== "undefined") {
    localStorage.setItem(TRADES_STORAGE_KEY, data);
  } else {
    await AsyncStorage.setItem(TRADES_STORAGE_KEY, data);
  }
}

function normalize(trades: Trade[]): TradeState {
  const byId: Record<string, Trade> = {};
  const allIds: string[] = [];
  for (const trade of trades) {
    byId[trade.id] = trade;
    allIds.push(trade.id);
  }
  return { byId, allIds };
}

function denormalize(state: TradeState): Trade[] {
  return state.allIds.map((id) => state.byId[id]);
}

// ============ Store Class ============

class TradeStore {
  private state: TradeState = { byId: {}, allIds: [] };
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
      if (e.key === TRADES_STORAGE_KEY && e.newValue) {
        const rawTrades: Partial<Trade>[] = JSON.parse(e.newValue);
        const trades = rawTrades.map(normalizeTrade);
        this.state = normalize(trades);
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

  getSnapshot = (): TradeState => {
    return this.state;
  };

  getServerSnapshot = (): TradeState => {
    return this.state;
  };

  // ============ Selectors ============

  getAllTrades(userId: string): Trade[] {
    return this.state.allIds
      .map((id) => this.state.byId[id])
      .filter((t) => t.user_id === userId && !t.deleted_at)
      .sort(
        (a, b) =>
          new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
      );
  }

  getTradeById(id: string): Trade | undefined {
    return this.state.byId[id];
  }

  /**
   * Get count of trades for a specific task in a given time period (days)
   */
  getTradesInPeriod(userId: string, taskId: string, days: number): number {
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - days);

    return this.state.allIds
      .map((id) => this.state.byId[id])
      .filter(
        (t) =>
          t.user_id === userId &&
          t.task_id === taskId &&
          !t.deleted_at &&
          new Date(t.created_at) >= cutoff,
      ).length;
  }

  // ============ Mutations ============

  async createTrade(userId: string, input: TradeInput): Promise<Trade> {
    const now = new Date().toISOString();
    const id = generateUUID();

    const trade: Trade = {
      id,
      user_id: userId,
      task_id: input.task_id ?? null,
      reward_id: input.reward_id ?? null,
      amount: input.amount,
      created_at: now,
      updated_at: now,
      deleted_at: null,
    };

    // Update state
    this.state = {
      byId: { ...this.state.byId, [id]: trade },
      allIds: [id, ...this.state.allIds],
    };

    // Persist and notify
    await writeStorage(this.state);
    await markTradeDirty(id);
    this.notify();

    return trade;
  }

  // ============ Sync Helpers ============

  async mergeTrades(
    serverTrades: Partial<Trade>[],
    userId?: string,
  ): Promise<void> {
    const newById = { ...this.state.byId };
    const existingIds = new Set(this.state.allIds);

    for (const rawTrade of serverTrades) {
      const trade = normalizeTrade(rawTrade);
      const existing = newById[trade.id];
      const user_id = existing?.user_id || userId || trade.user_id;
      newById[trade.id] = { ...trade, user_id };
      if (!existingIds.has(trade.id)) {
        existingIds.add(trade.id);
      }
    }

    this.state = {
      byId: newById,
      allIds: Array.from(existingIds),
    };

    await writeStorage(this.state);
    this.notify();
  }

  getDirtyTrades(dirtyIds: Set<string>): Trade[] {
    return Array.from(dirtyIds)
      .map((id) => this.state.byId[id])
      .filter(Boolean);
  }

  async reload(): Promise<void> {
    this.state = await readStorageAsync();
    this.notify();
  }

  async clearAllTrades(): Promise<void> {
    this.state = { byId: {}, allIds: [] };
    await writeStorage(this.state);
    this.notify();
  }

  /**
   * Update user_id for all trades (used when merging anonymous trades to a logged-in account).
   */
  async updateAllTradesUserId(
    newUserId: string,
    fromUserId?: string,
  ): Promise<string[]> {
    const tradeIds: string[] = [];
    const newById: Record<string, Trade> = {};

    for (const id of this.state.allIds) {
      const trade = this.state.byId[id];
      if (fromUserId && trade.user_id !== fromUserId) {
        newById[id] = trade;
        continue;
      }
      newById[id] = { ...trade, user_id: newUserId };
      tradeIds.push(id);
    }

    this.state = {
      byId: newById,
      allIds: this.state.allIds,
    };

    await writeStorage(this.state);

    if (tradeIds.length > 0) {
      await markTradesDirty(tradeIds);
    }

    this.notify();

    return tradeIds;
  }
}

// ============ Utilities ============

function generateUUID(): string {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

// ============ Singleton Export ============

export const tradeStore = new TradeStore();
