import { api } from "../api";
import { habitStore } from "../store/habitStore";
import { tradeStore } from "../store/tradeStore";
import { tagStore } from "../store/tagStore";
import { habitTagStore } from "../store/habitTagStore";
import { balanceStore } from "../store/balanceStore";
import { userStore } from "../store/userStore";
import { habitTagKey } from "../habitTag";
import {
  getSyncState,
  clearAllDirty,
  setLastSyncTime,
  checkAndPrepareFullSyncIfNeeded,
  recordFullSyncCompleted,
  clearFullSyncTimestamp,
} from "./syncStorage";
import type {
  SyncCallbacks,
  SyncInput,
  SyncHabitInput,
  SyncTradeInput,
  SyncTagInput,
  SyncHabitTagInput,
} from "./types";

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
      const syncState = await getSyncState();
      const response = await api.sync(syncState.lastSync);

      // Filter out dirty entities to preserve local changes
      const dirtyHabitIds = new Set(syncState.dirty.habits);
      const dirtyTradeIds = new Set(syncState.dirty.trades);
      const dirtyTagIds = new Set(syncState.dirty.tags || []);
      const dirtyHabitTagKeys = new Set(syncState.dirty.habitTags || []);
      const cleanHabits = response.habits.filter((h) => !dirtyHabitIds.has(h.id));
      const cleanTrades = response.trades.filter((t) => !dirtyTradeIds.has(t.id));
      const cleanTags = (response.tags || []).filter((t) => !dirtyTagIds.has(t.id));
      const cleanHabitTags = (response.habitTags || []).filter(
        (ht) => !dirtyHabitTagKeys.has(habitTagKey(ht.habit_id, ht.tag_id)),
      );

      // Merge only non-dirty entities
      if (cleanHabits.length > 0) {
        await habitStore.mergeHabits(cleanHabits, this.userId);
      }
      if (cleanTrades.length > 0) {
        await tradeStore.mergeTrades(cleanTrades, this.userId);
      }
      if (cleanTags.length > 0) {
        await tagStore.merge(cleanTags, this.userId);
      }
      if (cleanHabitTags.length > 0) {
        await habitTagStore.merge(cleanHabitTags, this.userId);
      }
      await balanceStore.setBalance(
        response.balance.soy_balance,
        response.balance.tofu_balance,
      );
      await userStore.setUser(response.email, response.isPremium);

      await setLastSyncTime(response.server_time);
      this.callbacks.onSyncComplete(response.server_time);
    } catch (error) {
      // Silently fail background sync - don't update status
      console.debug("Background sync failed:", error);
    }
  }

  /**
   * Called after any local habit change.
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

      // Step 2: Snapshot dirty entities BEFORE pulling
      // This preserves local changes that haven't been pushed yet
      const dirtyHabitIds = new Set(syncState.dirty.habits);
      const dirtyTradeIds = new Set(syncState.dirty.trades);
      const dirtyTagIds = new Set(syncState.dirty.tags || []);
      const dirtyHabitTagKeys = new Set(syncState.dirty.habitTags || []);
      const dirtyHabits = habitStore.getDirtyHabits(dirtyHabitIds);
      const dirtyTrades = tradeStore.getDirtyTrades(dirtyTradeIds);
      const dirtyTags = tagStore.getDirty(dirtyTagIds);
      const dirtyHabitTags = habitTagStore.getDirty(dirtyHabitTagKeys);

      // Step 3: Pull all changes from server
      const pullResponse = await api.sync(syncState.lastSync);

      // Step 4: Merge all entities (order matters: habits/tags before trades/habitTags)
      if (pullResponse.habits.length > 0) {
        await habitStore.mergeHabits(pullResponse.habits, this.userId);
      }
      if (pullResponse.trades.length > 0) {
        await tradeStore.mergeTrades(pullResponse.trades, this.userId);
      }
      if ((pullResponse.tags || []).length > 0) {
        await tagStore.merge(pullResponse.tags, this.userId);
      }
      if ((pullResponse.habitTags || []).length > 0) {
        await habitTagStore.merge(pullResponse.habitTags, this.userId);
      }
      await balanceStore.setBalance(
        pullResponse.balance.soy_balance,
        pullResponse.balance.tofu_balance,
      );
      await userStore.setUser(pullResponse.email, pullResponse.isPremium);

      // Step 5: Push dirty entities if any
      const hasDirty =
        dirtyHabits.length > 0 ||
        dirtyTrades.length > 0 ||
        dirtyTags.length > 0 ||
        dirtyHabitTags.length > 0;
      if (hasDirty) {
        const input = this.buildSyncInput(
          dirtyHabits,
          dirtyTrades,
          dirtyTags,
          dirtyHabitTags,
        );
        const pushResponse = await api.syncPush(input);

        // Step 6: Merge server's resolved versions
        if (pushResponse.habits.length > 0) {
          await habitStore.mergeHabits(pushResponse.habits, this.userId);
        }
        if (pushResponse.trades.length > 0) {
          await tradeStore.mergeTrades(pushResponse.trades, this.userId);
        }
        if ((pushResponse.tags || []).length > 0) {
          await tagStore.merge(pushResponse.tags, this.userId);
        }
        if ((pushResponse.habitTags || []).length > 0) {
          await habitTagStore.merge(pushResponse.habitTags, this.userId);
        }
        await balanceStore.setBalance(
          pushResponse.balance.soy_balance,
          pushResponse.balance.tofu_balance,
        );
        await userStore.setUser(pushResponse.email, pushResponse.isPremium);
      }

      // Step 7: Clear dirty flags and update timestamp
      await clearAllDirty();
      await setLastSyncTime(pullResponse.server_time);

      // Step 8: Purge soft-deleted entities
      await habitStore.purgeDeletedHabits();
      await tradeStore.purgeDeletedTrades();
      await tagStore.purgeDeleted();
      await habitTagStore.purgeDeleted();

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
    habits: ReturnType<typeof habitStore.getDirtyHabits>,
    trades: ReturnType<typeof tradeStore.getDirtyTrades>,
    tags: ReturnType<typeof tagStore.getDirty>,
    habitTags: ReturnType<typeof habitTagStore.getDirty>,
  ): SyncInput {
    const habitInputs: SyncHabitInput[] | undefined =
      habits.length > 0
        ? habits.map((h) => ({
            id: h.id,
            name: h.name,
            description: h.description,
            createdAt: h.created_at,
            updatedAt: h.updated_at,
            deletedAt: h.deleted_at,
            hiddenUntil: h.hidden_until,
            minDailyFrequency: h.min_daily_frequency,
            difficultyRank: h.difficulty_rank,
          }))
        : undefined;

    const tradeInputs: SyncTradeInput[] | undefined =
      trades.length > 0
        ? trades.map((t) => ({
            id: t.id,
            habitId: t.habit_id,
            rewardId: t.reward_id,
            amount: t.amount,
            createdAt: t.created_at,
            deletedAt: t.deleted_at,
          }))
        : undefined;

    const tagInputs: SyncTagInput[] | undefined =
      tags.length > 0
        ? tags.map((t) => ({
            id: t.id,
            name: t.name,
            colorHex: t.color_hex,
            createdAt: t.created_at,
            updatedAt: t.updated_at,
            deletedAt: t.deleted_at,
          }))
        : undefined;

    const habitTagInputs: SyncHabitTagInput[] | undefined =
      habitTags.length > 0
        ? habitTags.map((ht) => ({
            habitId: ht.habit_id,
            tagId: ht.tag_id,
            createdAt: ht.created_at,
            updatedAt: ht.updated_at,
            deletedAt: ht.deleted_at,
          }))
        : undefined;

    return {
      habits: habitInputs,
      trades: tradeInputs,
      tags: tagInputs,
      habitTags: habitTagInputs,
    };
  }
}
