import type { Task } from "../task";

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
