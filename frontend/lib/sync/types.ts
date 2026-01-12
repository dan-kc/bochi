import type { Task } from "../task";
import type { Trade } from "../trade";

export type SyncStatus = "idle" | "syncing" | "synced" | "error";

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

export interface SyncCallbacks {
  onStatusChange: (status: SyncStatus, error?: string) => void;
  onSyncComplete: (serverTime: string) => void;
}

// Trade sync types
export interface SyncPullTradesResponse {
  trades: Trade[];
  server_time: string;
}

export interface SyncPushTradesResponse {
  trades: Trade[];
  server_time: string;
  new_balance: number;
}

export interface BalanceResponse {
  soy_balance: number;
  tofu_balance: number;
}
