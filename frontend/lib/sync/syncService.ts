import { api } from "../api";
import { taskStore } from "../store/taskStore";
import {
  getDirtyTaskIds,
  clearAllDirtyFlags,
  getLastSyncTime,
  setLastSyncTime,
  checkAndPrepareFullSyncIfNeeded,
  recordFullSyncCompleted,
  clearFullSyncTimestamp,
} from "./syncStorage";
import type { SyncCallbacks } from "./types";

const DEBOUNCE_MS = 2000;
const BACKGROUND_SYNC_INTERVAL_MS = 5000; // 5 seconds
const FULL_SYNC_RESET_INTERVAL_MS = 24 * 60 * 60 * 1000; // 24 hours

export class SyncService {
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;
  private backgroundSyncInterval: ReturnType<typeof setInterval> | null = null;
  private fullSyncResetInterval: ReturnType<typeof setInterval> | null = null;
  private isSyncing = false;
  private callbacks: SyncCallbacks;
  private userId: string;

  constructor(callbacks: SyncCallbacks, userId: string) {
    this.callbacks = callbacks;
    this.userId = userId;
    this.startBackgroundSync();
    this.startFullSyncResetTimer();
  }

  private startBackgroundSync(): void {
    // Start periodic background sync (read-only pull)
    this.backgroundSyncInterval = setInterval(() => {
      this.executeBackgroundPull();
    }, BACKGROUND_SYNC_INTERVAL_MS);
  }

  private startFullSyncResetTimer(): void {
    // Every 24 hours, clear the full sync timestamp to force a full sync
    this.fullSyncResetInterval = setInterval(() => {
      console.log("[Sync] 24-hour timer: clearing full sync timestamp");
      clearFullSyncTimestamp();
    }, FULL_SYNC_RESET_INTERVAL_MS);
  }

  private async executeBackgroundPull(): Promise<void> {
    // Skip if already syncing or no network
    if (this.isSyncing) return;
    if (typeof navigator !== "undefined" && !navigator.onLine) return;

    try {
      const lastSync = await getLastSyncTime();
      const pullResponse = await api.pullTasks(lastSync);

      if (pullResponse.tasks.length > 0) {
        await taskStore.mergeTasks(pullResponse.tasks, this.userId);
      }

      await setLastSyncTime(pullResponse.server_time);
      this.callbacks.onSyncComplete(pullResponse.server_time);
    } catch (error) {
      // Silently fail background sync - don't update status
      console.debug("Background sync failed:", error);
    }
  }

  /**
   * Called after any local task change.
   * Starts/resets the debounce timer.
   */
  notifyChange(): void {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
    }
    this.debounceTimer = setTimeout(() => {
      this.executeSync();
    }, DEBOUNCE_MS);
  }

  /**
   * Manually trigger sync (e.g., on app foreground or retry button).
   */
  triggerSync(): void {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    this.executeSync();
  }

  /**
   * Trigger sync and wait for completion.
   * Returns a promise that resolves when sync finishes (success or error).
   */
  async syncAndWait(): Promise<void> {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    await this.executeSync();
  }

  /**
   * Cancel any pending sync and stop background sync (e.g., on logout).
   */
  cancel(): void {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    if (this.backgroundSyncInterval) {
      clearInterval(this.backgroundSyncInterval);
      this.backgroundSyncInterval = null;
    }
    if (this.fullSyncResetInterval) {
      clearInterval(this.fullSyncResetInterval);
      this.fullSyncResetInterval = null;
    }
  }

  private async executeSync(): Promise<void> {
    // Prevent concurrent syncs
    if (this.isSyncing) {
      return;
    }

    this.isSyncing = true;
    this.callbacks.onStatusChange("syncing");

    try {
      // Step 0: Check if periodic full sync is needed (every 24h)
      // This clears lastSyncTime if it's been too long since last full sync
      const isFullSync = await checkAndPrepareFullSyncIfNeeded();

      // Step 1: Pull remote changes
      const lastSync = await getLastSyncTime();
      const pullResponse = await api.pullTasks(lastSync);

      // Step 2: Merge server tasks into store
      if (pullResponse.tasks.length > 0) {
        await taskStore.mergeTasks(pullResponse.tasks, this.userId);
      }

      // Step 3: Push dirty local tasks
      const dirtyIds = await getDirtyTaskIds();
      if (dirtyIds.size > 0) {
        const dirtyTasks = taskStore.getDirtyTasks(dirtyIds);
        if (dirtyTasks.length > 0) {
          const pushResponse = await api.pushTasks(dirtyTasks);
          // Apply server's resolved versions
          if (pushResponse.tasks.length > 0) {
            await taskStore.mergeTasks(pushResponse.tasks, this.userId);
          }
        }
      }

      // Step 4: Clear dirty flags and purge deleted tasks
      await clearAllDirtyFlags();
      await taskStore.purgeDeletedTasks();

      // Step 5: Update last sync time and notify success
      await setLastSyncTime(pullResponse.server_time);
      this.callbacks.onStatusChange("synced");
      this.callbacks.onSyncComplete(pullResponse.server_time);

      // Step 6: Record full sync completion if this was a full sync
      if (isFullSync || lastSync === null) {
        await recordFullSyncCompleted();
      }
    } catch (error) {
      console.error("Sync failed:", error);
      const message =
        error instanceof Error
          ? error.message
          : ((error as { message?: string })?.message ?? "Sync failed");
      this.callbacks.onStatusChange("error", message);
    } finally {
      this.isSyncing = false;
    }
  }
}
