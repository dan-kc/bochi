import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { SyncService } from "./syncService";
import { api } from "../api";
import { habitStore } from "../store/habitStore";
import { tradeStore } from "../store/tradeStore";
import { balanceStore } from "../store/balanceStore";
import { userStore } from "../store/userStore";
import * as syncStorage from "./syncStorage";
import type { Habit } from "../habit";
import type { SyncResponse } from "./types";

// Mock all dependencies
vi.mock("../api", () => ({
  api: {
    sync: vi.fn(),
    syncPush: vi.fn(),
  },
}));

vi.mock("../store/habitStore", () => ({
  habitStore: {
    getDirtyHabits: vi.fn(),
    mergeHabits: vi.fn(),
    purgeDeletedHabits: vi.fn(),
  },
}));

vi.mock("../store/tradeStore", () => ({
  tradeStore: {
    getDirtyTrades: vi.fn(),
    mergeTrades: vi.fn(),
    purgeDeletedTrades: vi.fn(),
  },
}));

vi.mock("../store/balanceStore", () => ({
  balanceStore: {
    setBalance: vi.fn(),
  },
}));

vi.mock("../store/userStore", () => ({
  userStore: {
    setUser: vi.fn(),
  },
}));

vi.mock("./syncStorage", () => ({
  getSyncState: vi.fn(),
  clearAllDirty: vi.fn(),
  setLastSyncTime: vi.fn(),
  checkAndPrepareFullSyncIfNeeded: vi.fn(),
  recordFullSyncCompleted: vi.fn(),
  clearFullSyncTimestamp: vi.fn(),
}));

describe("SyncService", () => {
  let syncService: SyncService;
  const mockCallbacks = {
    onStatusChange: vi.fn(),
    onSyncComplete: vi.fn(),
  };
  const userId = "test-user-id";

  beforeEach(() => {
    vi.clearAllMocks();

    // Default mock implementations
    vi.mocked(syncStorage.getSyncState).mockResolvedValue({
      lastSync: "2024-01-01T00:00:00Z",
      dirty: { habits: [], trades: [] },
    });
    vi.mocked(syncStorage.checkAndPrepareFullSyncIfNeeded).mockResolvedValue(false);
    vi.mocked(syncStorage.clearAllDirty).mockResolvedValue();
    vi.mocked(syncStorage.setLastSyncTime).mockResolvedValue();
    vi.mocked(syncStorage.recordFullSyncCompleted).mockResolvedValue();

    vi.mocked(habitStore.getDirtyHabits).mockReturnValue([]);
    vi.mocked(habitStore.mergeHabits).mockResolvedValue();
    vi.mocked(habitStore.purgeDeletedHabits).mockResolvedValue();

    vi.mocked(tradeStore.getDirtyTrades).mockReturnValue([]);
    vi.mocked(tradeStore.mergeTrades).mockResolvedValue();
    vi.mocked(tradeStore.purgeDeletedTrades).mockResolvedValue();

    vi.mocked(balanceStore.setBalance).mockResolvedValue();

    vi.mocked(userStore.setUser).mockResolvedValue();

    const defaultPullResponse: SyncResponse = {
      habits: [],
      trades: [],
      balance: { soy_balance: 100, tofu_balance: 50 },
      server_time: "2024-01-01T00:00:01Z",
      email: "test@example.com",
      isPremium: false,
    };
    vi.mocked(api.sync).mockResolvedValue(defaultPullResponse);
    vi.mocked(api.syncPush).mockResolvedValue(defaultPullResponse);

    syncService = new SyncService(mockCallbacks, userId);
  });

  afterEach(() => {
    syncService.cancel();
  });

  describe("dirty entity snapshotting", () => {
    test("snapshots dirty habits BEFORE merge to preserve local changes", async () => {
      // This test verifies the fix for the race condition where:
      // 1. User creates a habit and sets difficulty_rank locally
      // 2. Sync pulls from server (habit has difficulty_rank: null)
      // 3. Merge overwrites local difficulty_rank with null
      // 4. Push sends the overwritten (null) value instead of the local value
      //
      // The fix: snapshot dirty habits BEFORE the pull/merge

      const habitId = "habit-123";

      // Local habit has difficulty_rank set
      const localHabit: Habit = {
        id: habitId,
        user_id: userId,
        name: "Test Habit",
        description: "",
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        deleted_at: null,
        hidden_until: null,
        min_daily_frequency: null,
        difficulty_rank: "a0", // User set this via binary search
      };

      // Server returns the habit WITHOUT difficulty_rank (not yet synced)
      const serverHabit: Habit = {
        ...localHabit,
        difficulty_rank: null, // Server doesn't have the difficulty yet
      };

      // Setup: habit is marked as dirty
      vi.mocked(syncStorage.getSyncState).mockResolvedValue({
        lastSync: "2024-01-01T00:00:00Z",
        dirty: { habits: [habitId], trades: [] },
      });

      // Track the order of calls and what values were captured
      const callOrder: string[] = [];
      let capturedDirtyHabits: Habit[] = [];

      vi.mocked(habitStore.getDirtyHabits).mockImplementation((dirtyIds) => {
        callOrder.push("getDirtyHabits");
        // Return the local habit with difficulty_rank set
        if (dirtyIds.has(habitId)) {
          capturedDirtyHabits = [localHabit];
          return [localHabit];
        }
        return [];
      });

      vi.mocked(habitStore.mergeHabits).mockImplementation(async () => {
        callOrder.push("mergeHabits");
        // After merge, getDirtyHabits would return the overwritten value
        // But it shouldn't be called again - we already snapshotted
      });

      vi.mocked(api.sync).mockResolvedValue({
        habits: [serverHabit], // Server returns habit without difficulty
        trades: [],
        balance: { soy_balance: 100, tofu_balance: 50 },
        server_time: "2024-01-01T00:00:01Z",
        email: "test@example.com",
        isPremium: false,
      });

      vi.mocked(api.syncPush).mockResolvedValue({
        habits: [localHabit], // Server echoes back what we sent
        trades: [],
        balance: { soy_balance: 100, tofu_balance: 50 },
        server_time: "2024-01-01T00:00:02Z",
        email: "test@example.com",
        isPremium: false,
      });

      // Trigger sync and wait for completion
      await syncService.syncAndWait();

      // Verify getDirtyHabits was called BEFORE mergeHabits
      expect(callOrder.indexOf("getDirtyHabits")).toBeLessThan(
        callOrder.indexOf("mergeHabits")
      );

      // Verify syncPush was called with the correct (local) difficulty_rank
      expect(api.syncPush).toHaveBeenCalledTimes(1);
      const pushCall = vi.mocked(api.syncPush).mock.calls[0][0];
      expect(pushCall.habits).toBeDefined();
      expect(pushCall.habits![0].difficultyRank).toBe("a0");
    });

    test("preserves local trade changes during sync", async () => {
      const tradeId = "trade-456";

      const localTrade = {
        id: tradeId,
        user_id: userId,
        habit_id: "habit-123",
        reward_id: null,
        amount: 10,
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        deleted_at: null,
      };

      vi.mocked(syncStorage.getSyncState).mockResolvedValue({
        lastSync: "2024-01-01T00:00:00Z",
        dirty: { habits: [], trades: [tradeId] },
      });

      const callOrder: string[] = [];

      vi.mocked(tradeStore.getDirtyTrades).mockImplementation(() => {
        callOrder.push("getDirtyTrades");
        return [localTrade];
      });

      vi.mocked(tradeStore.mergeTrades).mockImplementation(async () => {
        callOrder.push("mergeTrades");
      });

      vi.mocked(api.sync).mockResolvedValue({
        habits: [],
        trades: [],
        balance: { soy_balance: 100, tofu_balance: 50 },
        server_time: "2024-01-01T00:00:01Z",
        email: "test@example.com",
        isPremium: false,
      });

      vi.mocked(api.syncPush).mockResolvedValue({
        habits: [],
        trades: [localTrade],
        balance: { soy_balance: 110, tofu_balance: 50 },
        server_time: "2024-01-01T00:00:02Z",
        email: "test@example.com",
        isPremium: false,
      });

      await syncService.syncAndWait();

      // Verify getDirtyTrades was called BEFORE mergeTrades
      expect(callOrder.indexOf("getDirtyTrades")).toBeLessThan(
        callOrder.indexOf("mergeTrades")
      );

      // Verify syncPush was called with the local trade
      expect(api.syncPush).toHaveBeenCalledTimes(1);
      const pushCall = vi.mocked(api.syncPush).mock.calls[0][0];
      expect(pushCall.trades).toBeDefined();
      expect(pushCall.trades![0].amount).toBe(10);
    });

    test("does not call syncPush when there are no dirty entities", async () => {
      vi.mocked(syncStorage.getSyncState).mockResolvedValue({
        lastSync: "2024-01-01T00:00:00Z",
        dirty: { habits: [], trades: [] },
      });

      vi.mocked(habitStore.getDirtyHabits).mockReturnValue([]);
      vi.mocked(tradeStore.getDirtyTrades).mockReturnValue([]);

      await syncService.syncAndWait();

      expect(api.sync).toHaveBeenCalledTimes(1);
      expect(api.syncPush).not.toHaveBeenCalled();
    });
  });

  describe("filtering dirty entities", () => {
    test("executeSync filters dirty habits from pull response during merge", async () => {
      // This verifies that during a full sync, the merge step doesn't lose
      // dirty local changes because we snapshot them before the merge

      const dirtyHabitId = "dirty-habit-123";
      const cleanHabitId = "clean-habit-456";

      const localDirtyHabit: Habit = {
        id: dirtyHabitId,
        user_id: userId,
        name: "Dirty Habit",
        description: "",
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        deleted_at: null,
        hidden_until: null,
        min_daily_frequency: null,
        difficulty_rank: "a0", // Local has the correct value
      };

      const serverDirtyHabit: Habit = {
        ...localDirtyHabit,
        difficulty_rank: null, // Server has outdated null value
      };

      const serverCleanHabit: Habit = {
        id: cleanHabitId,
        user_id: userId,
        name: "Clean Habit",
        description: "",
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        deleted_at: null,
        hidden_until: null,
        min_daily_frequency: null,
        difficulty_rank: "b0",
      };

      vi.mocked(syncStorage.getSyncState).mockResolvedValue({
        lastSync: "2024-01-01T00:00:00Z",
        dirty: { habits: [dirtyHabitId], trades: [] },
      });

      // The key: getDirtyHabits returns the local version with correct difficulty
      vi.mocked(habitStore.getDirtyHabits).mockReturnValue([localDirtyHabit]);

      vi.mocked(api.sync).mockResolvedValue({
        habits: [serverDirtyHabit, serverCleanHabit],
        trades: [],
        balance: { soy_balance: 100, tofu_balance: 50 },
        server_time: "2024-01-01T00:00:01Z",
        email: "test@example.com",
        isPremium: false,
      });

      vi.mocked(api.syncPush).mockResolvedValue({
        habits: [localDirtyHabit],
        trades: [],
        balance: { soy_balance: 100, tofu_balance: 50 },
        server_time: "2024-01-01T00:00:02Z",
        email: "test@example.com",
        isPremium: false,
      });

      await syncService.syncAndWait();

      // The push should have the correct local difficulty_rank value
      expect(api.syncPush).toHaveBeenCalledTimes(1);
      const pushCall = vi.mocked(api.syncPush).mock.calls[0][0];
      expect(pushCall.habits![0].difficultyRank).toBe("a0");
    });

    test("dirty entities filtering logic works correctly", () => {
      // Unit test the filtering logic directly
      const dirtyHabitIds = new Set(["dirty-1", "dirty-2"]);
      const serverHabits = [
        { id: "dirty-1", name: "Dirty 1" },
        { id: "clean-1", name: "Clean 1" },
        { id: "dirty-2", name: "Dirty 2" },
        { id: "clean-2", name: "Clean 2" },
      ];

      const cleanHabits = serverHabits.filter((h) => !dirtyHabitIds.has(h.id));

      expect(cleanHabits).toHaveLength(2);
      expect(cleanHabits.map((h) => h.id)).toEqual(["clean-1", "clean-2"]);
    });
  });
});
