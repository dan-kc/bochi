import type { Task } from "../task";
import type { Trade } from "../trade";

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
  tasks: Task[];
  trades: Trade[];
  balance: BalanceResponse;
  server_time: string;
}

export interface SyncTaskInput {
  id: string;
  name: string;
  description: string;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
  hiddenUntil: string | null;
  dueBy: string | null;
  minDailyFrequency: number | null;
  difficultyRank: string | null;
  completedAt: string | null;
  habit: boolean;
}

export interface SyncTradeInput {
  id: string;
  taskId: string | null;
  rewardId: string | null;
  amount: number;
  createdAt: string;
  deletedAt: string | null;
}

export interface SyncInput {
  tasks?: SyncTaskInput[];
  trades?: SyncTradeInput[];
}

// ============================================================================
// Sync State (localStorage)
// ============================================================================

export interface SyncState {
  lastSync: string | null;
  dirty: {
    tasks: string[];
    trades: string[];
  };
}

// ============================================================================
// Legacy Types (to be removed after cleanup)
// ============================================================================

export interface SyncPullResponse {
  tasks: Task[];
  server_time: string;
}

export interface SyncPushRequest {
  tasks: Task[];
}

export interface SyncPushResponse {
  tasks: Task[];
  server_time: string;
}

export interface SyncPullTradesResponse {
  trades: Trade[];
  server_time: string;
}

export interface SyncPushTradesResponse {
  trades: Trade[];
  server_time: string;
  new_balance: number;
}
