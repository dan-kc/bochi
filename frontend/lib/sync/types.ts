import type { Habit } from "../habit";
import type { Trade } from "../trade";
import type { Tag } from "../tag";
import type { HabitTag } from "../habitTag";

export type SyncStatus = "idle" | "syncing" | "synced" | "error";

export interface SyncCallbacks {
  onStatusChange: (status: SyncStatus, error?: string) => void;
  onSyncComplete: (serverTime: string) => void;
}

export interface BalanceResponse {
  soy_balance: number;
  tofu_balance: number;
}

// ============================================================================
// Unified Sync Types
// ============================================================================

export interface SyncResponse {
  habits: Habit[];
  trades: Trade[];
  tags: Tag[];
  habitTags: HabitTag[];
  balance: BalanceResponse;
  server_time: string;
  email: string | null;
  isPremium: boolean;
}

export interface SyncHabitInput {
  id: string;
  name: string;
  description: string;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
  hiddenUntil: string | null;
  minDailyFrequency: number | null;
  difficultyRank: string | null;
}

export interface SyncTradeInput {
  id: string;
  habitId: string | null;
  rewardId: string | null;
  amount: number;
  createdAt: string;
  deletedAt: string | null;
}

export interface SyncTagInput {
  id: string;
  name: string;
  colorHex: string;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export interface SyncHabitTagInput {
  habitId: string;
  tagId: string;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export interface SyncInput {
  habits?: SyncHabitInput[];
  trades?: SyncTradeInput[];
  tags?: SyncTagInput[];
  habitTags?: SyncHabitTagInput[];
}

// ============================================================================
// Sync State (localStorage)
// ============================================================================

export interface SyncState {
  lastSync: string | null;
  dirty: {
    habits: string[];
    trades: string[];
    tags: string[];
    habitTags: string[];
  };
}
