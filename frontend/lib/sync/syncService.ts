import { api } from "../api";
import { taskStore } from "../store/taskStore";
import { tradeStore } from "../store/tradeStore";
import { balanceStore } from "../store/balanceStore";
import {
  getSyncState,
  clearAllDirty,
  setLastSyncTime,
  checkAndPrepareFullSyncIfNeeded,
  recordFullSyncCompleted,
  clearFullSyncTimestamp,
  cleanupOldSyncStorage,
} from "./syncStorage";
import type { SyncCallbacks, SyncInput, SyncTaskInput, SyncTradeInput } from "./types";

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
    // Clean up old storage keys from previous implementation
    cleanupOldSyncStorage().catch(console.error);
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
      const syncState = await getSyncState();
      const response = await api.sync(syncState.lastSync);

      // Merge all entities
      if (response.tasks.length > 0) {
        await taskStore.mergeTasks(response.tasks, this.userId);
      }
      if (response.trades.length > 0) {
        await tradeStore.mergeTrades(response.trades, this.userId);
      }
      await balanceStore.setBalance(
        response.balance.soy_balance,
        response.balance.tofu_balance,
      );

      await setLastSyncTime(response.server_time);
      this.callbacks.onSyncComplete(response.server_time);
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
      const isFullSync = await checkAndPrepareFullSyncIfNeeded();

      // Step 1: Get current sync state
      const syncState = await getSyncState();

      // Step 2: Pull all changes from server
      const pullResponse = await api.sync(syncState.lastSync);

      // Step 3: Merge all entities (order matters: tasks before trades)
      if (pullResponse.tasks.length > 0) {
        await taskStore.mergeTasks(pullResponse.tasks, this.userId);
      }
      if (pullResponse.trades.length > 0) {
        await tradeStore.mergeTrades(pullResponse.trades, this.userId);
      }
      await balanceStore.setBalance(
        pullResponse.balance.soy_balance,
        pullResponse.balance.tofu_balance,
      );

      // Step 4: Gather dirty entities
      const dirtyTaskIds = new Set(syncState.dirty.tasks);
      const dirtyTradeIds = new Set(syncState.dirty.trades);
      const dirtyTasks = taskStore.getDirtyTasks(dirtyTaskIds);
      const dirtyTrades = tradeStore.getDirtyTrades(dirtyTradeIds);

      // Step 5: Push dirty entities if any
      if (dirtyTasks.length > 0 || dirtyTrades.length > 0) {
        const input = this.buildSyncInput(dirtyTasks, dirtyTrades);
        const pushResponse = await api.syncPush(input);

        // Step 6: Merge server's resolved versions
        if (pushResponse.tasks.length > 0) {
          await taskStore.mergeTasks(pushResponse.tasks, this.userId);
        }
        if (pushResponse.trades.length > 0) {
          await tradeStore.mergeTrades(pushResponse.trades, this.userId);
        }
        await balanceStore.setBalance(
          pushResponse.balance.soy_balance,
          pushResponse.balance.tofu_balance,
        );
      }

      // Step 7: Clear dirty flags and update timestamp
      await clearAllDirty();
      await setLastSyncTime(pullResponse.server_time);

      // Step 8: Purge soft-deleted entities
      await taskStore.purgeDeletedTasks();
      await tradeStore.purgeDeletedTrades();

      // Step 9: Notify success
      this.callbacks.onStatusChange("synced");
      this.callbacks.onSyncComplete(pullResponse.server_time);

      // Step 10: Record full sync completion if this was a full sync
      if (isFullSync || syncState.lastSync === null) {
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

  private buildSyncInput(
    tasks: ReturnType<typeof taskStore.getDirtyTasks>,
    trades: ReturnType<typeof tradeStore.getDirtyTrades>,
  ): SyncInput {
    const taskInputs: SyncTaskInput[] | undefined =
      tasks.length > 0
        ? tasks.map((t) => ({
            id: t.id,
            name: t.name,
            description: t.description,
            createdAt: t.created_at,
            updatedAt: t.updated_at,
            deletedAt: t.deleted_at,
            hiddenUntil: t.hidden_until,
            dueBy: t.due_by,
            minDailyFrequency: t.min_daily_frequency,
            difficultyRank: t.difficulty_rank,
            completedAt: t.completed_at,
            habit: t.habit,
          }))
        : undefined;

    const tradeInputs: SyncTradeInput[] | undefined =
      trades.length > 0
        ? trades.map((t) => ({
            id: t.id,
            taskId: t.task_id,
            rewardId: t.reward_id,
            amount: t.amount,
            createdAt: t.created_at,
            deletedAt: t.deleted_at,
          }))
        : undefined;

    return {
      tasks: taskInputs,
      trades: tradeInputs,
    };
  }
}
