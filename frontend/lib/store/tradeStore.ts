import type { Trade, TradeInput } from "../trade";
import { markTradeDirty, markTradesDirty } from "../sync/syncStorage";
import { EntityStore, generateUUID } from "./createStore";

const TRADES_STORAGE_KEY = "tofustash_trades";

// ============ Trade Normalization ============

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

// ============ Trade Store ============

class TradeStore extends EntityStore<Trade> {
  constructor() {
    super({
      storageKey: TRADES_STORAGE_KEY,
      normalize: normalizeTrade,
      markDirty: markTradeDirty,
      markManyDirty: markTradesDirty,
      enableVisibilityReload: true,
      enableAppStateReload: true,
    });
  }

  // ============ Trade-specific Selectors ============

  getAllTrades(userId: string): Trade[] {
    return this.getAll(userId);
  }

  getTradeById(id: string): Trade | undefined {
    return this.getById(id);
  }

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

  // ============ Trade Mutations ============

  async createTrade(userId: string, input: TradeInput): Promise<Trade> {
    const now = new Date().toISOString();
    const trade: Trade = {
      id: generateUUID(),
      user_id: userId,
      task_id: input.task_id ?? null,
      reward_id: input.reward_id ?? null,
      amount: input.amount,
      created_at: now,
      updated_at: now,
      deleted_at: null,
    };

    await this.addItem(trade);
    return trade;
  }

  // ============ Sync Helpers (aliases for compatibility) ============

  async mergeTrades(serverTrades: Partial<Trade>[], userId?: string): Promise<void> {
    return this.merge(serverTrades, userId);
  }

  getDirtyTrades(dirtyIds: Set<string>): Trade[] {
    return this.getDirty(dirtyIds);
  }

  async clearAllTrades(): Promise<void> {
    return this.clearAll();
  }

  async updateAllTradesUserId(newUserId: string, fromUserId?: string): Promise<string[]> {
    return this.updateAllUserId(newUserId, fromUserId);
  }

  async purgeDeletedTrades(): Promise<void> {
    return this.purgeDeleted();
  }
}

// ============ Singleton Export ============

export const tradeStore = new TradeStore();
