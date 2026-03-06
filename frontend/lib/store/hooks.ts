import { useSyncExternalStore, useCallback, useRef } from "react";
import { habitStore } from "./habitStore";
import { tagStore } from "./tagStore";
import { habitTagStore } from "./habitTagStore";
import { rewardStore } from "./rewardStore";
import { rewardTagStore } from "./rewardTagStore";
import { tradeStore } from "./tradeStore";
import type { Habit } from "../habit";
import type { Tag } from "../tag";
import type { Reward } from "../reward";
import type { Trade } from "../trade";

// ============ Core Subscription Hook ============

/**
 * Subscribe to the entire habit state.
 * Re-renders on ANY habit change.
 */
export function useHabitStore() {
  return useSyncExternalStore(
    habitStore.subscribe,
    habitStore.getSnapshot,
    habitStore.getServerSnapshot,
  );
}

// ============ Fine-Grained Hooks ============

/**
 * Subscribe to all habits for a user (filtered, sorted).
 * Only re-renders when the filtered list changes.
 */
export function useHabits(userId: string): Habit[] {
  const getSnapshot = useCallback(() => {
    return habitStore.getAllHabits(userId);
  }, [userId]);

  // Use a ref to cache the previous result for shallow comparison
  const cacheRef = useRef<{ habits: Habit[]; serialized: string }>({
    habits: [],
    serialized: "[]",
  });

  const getSnapshotWithCache = useCallback(() => {
    const habits = habitStore.getAllHabits(userId);
    // Serialize for comparison (only IDs and updated_at for efficiency)
    const serialized = JSON.stringify(
      habits.map((h) => `${h.id}:${h.updated_at}`),
    );

    if (serialized !== cacheRef.current.serialized) {
      cacheRef.current = { habits, serialized };
    }
    return cacheRef.current.habits;
  }, [userId]);

  return useSyncExternalStore(
    habitStore.subscribe,
    getSnapshotWithCache,
    getSnapshotWithCache,
  );
}

/**
 * Subscribe to a single habit by ID.
 * Only re-renders when THIS specific habit changes.
 */
export function useHabit(habitId: string): Habit | undefined {
  const getSnapshot = useCallback(() => {
    return habitStore.getHabitById(habitId);
  }, [habitId]);

  // Cache to prevent unnecessary re-renders
  const cacheRef = useRef<{ habit: Habit | undefined; updatedAt: string }>({
    habit: undefined,
    updatedAt: "",
  });

  const getSnapshotWithCache = useCallback(() => {
    const habit = habitStore.getHabitById(habitId);
    const updatedAt = habit?.updated_at ?? "";

    if (updatedAt !== cacheRef.current.updatedAt) {
      cacheRef.current = { habit, updatedAt };
    }
    return cacheRef.current.habit;
  }, [habitId]);

  return useSyncExternalStore(
    habitStore.subscribe,
    getSnapshotWithCache,
    getSnapshotWithCache,
  );
}

/**
 * Subscribe to habit count for a user.
 * Only re-renders when count changes.
 */
export function useHabitCount(userId: string): number {
  const getSnapshot = useCallback(() => {
    return habitStore.getAllHabits(userId).length;
  }, [userId]);

  return useSyncExternalStore(habitStore.subscribe, getSnapshot, getSnapshot);
}

/**
 * Subscribe to habits sorted by difficulty for a user.
 * Sorted from hardest to easiest, with unranked habits at the bottom.
 */
export function useHabitsSortedByDifficulty(userId: string): Habit[] {
  // Use a ref to cache the previous result for shallow comparison
  const cacheRef = useRef<{ habits: Habit[]; serialized: string }>({
    habits: [],
    serialized: "[]",
  });

  const getSnapshotWithCache = useCallback(() => {
    const habits = habitStore.getHabitsSortedByDifficulty(userId);
    // Use updated_at to detect any habit field change (not just difficulty_rank)
    const serialized = JSON.stringify(
      habits.map((h) => `${h.id}:${h.updated_at}`),
    );

    if (serialized !== cacheRef.current.serialized) {
      cacheRef.current = { habits, serialized };
    }
    return cacheRef.current.habits;
  }, [userId]);

  return useSyncExternalStore(
    habitStore.subscribe,
    getSnapshotWithCache,
    getSnapshotWithCache,
  );
}

// ============ Actions (no subscription, just mutations) ============

export function useHabitActions() {
  return {
    createHabit: habitStore.createHabit.bind(habitStore),
    updateHabit: habitStore.updateHabit.bind(habitStore),
    deleteHabit: habitStore.deleteHabit.bind(habitStore),
    reload: habitStore.reload.bind(habitStore),
  };
}

// ============ Tag Hooks ============

/**
 * Subscribe to all tags for a user.
 * Only re-renders when the tag list changes.
 */
export function useTags(userId: string): Tag[] {
  const cacheRef = useRef<{ tags: Tag[]; serialized: string }>({
    tags: [],
    serialized: "[]",
  });

  const getSnapshotWithCache = useCallback(() => {
    const tags = tagStore.getAllTags(userId);
    const serialized = JSON.stringify(
      tags.map((t) => `${t.id}:${t.updated_at}`),
    );

    if (serialized !== cacheRef.current.serialized) {
      cacheRef.current = { tags, serialized };
    }
    return cacheRef.current.tags;
  }, [userId]);

  return useSyncExternalStore(
    tagStore.subscribe,
    getSnapshotWithCache,
    getSnapshotWithCache,
  );
}

/**
 * Subscribe to all tags including deleted ones for a user.
 * Useful for tag selection modal with restore option.
 */
export function useAllTagsIncludingDeleted(userId: string): Tag[] {
  const cacheRef = useRef<{ tags: Tag[]; serialized: string }>({
    tags: [],
    serialized: "[]",
  });

  const getSnapshotWithCache = useCallback(() => {
    const tags = tagStore.getAllTagsIncludingDeleted(userId);
    const serialized = JSON.stringify(
      tags.map((t) => `${t.id}:${t.updated_at}:${t.deleted_at ?? ""}`),
    );

    if (serialized !== cacheRef.current.serialized) {
      cacheRef.current = { tags, serialized };
    }
    return cacheRef.current.tags;
  }, [userId]);

  return useSyncExternalStore(
    tagStore.subscribe,
    getSnapshotWithCache,
    getSnapshotWithCache,
  );
}

/**
 * Subscribe to tags for a specific habit.
 * Only re-renders when THIS habit's tags change.
 */
export function useTagsForHabit(habitId: string): Tag[] {
  const cacheRef = useRef<{ tags: Tag[]; serialized: string }>({
    tags: [],
    serialized: "[]",
  });

  // Combined snapshot that gets tag IDs and resolves them to tags
  // We need to subscribe to both stores, so we combine the subscription
  const getSnapshot = useCallback(() => {
    const tagIds = habitTagStore.getTagIdsForHabit(habitId);
    const tags = tagIds
      .map((id) => tagStore.getTagById(id))
      .filter((t): t is Tag => t != null && !t.deleted_at);

    const serialized = JSON.stringify(
      tags.map((t) => `${t.id}:${t.updated_at}`),
    );

    if (serialized !== cacheRef.current.serialized) {
      cacheRef.current = { tags, serialized };
    }
    return cacheRef.current.tags;
  }, [habitId]);

  // Subscribe to habitTagStore changes
  useSyncExternalStore(habitTagStore.subscribe, getSnapshot, getSnapshot);

  // Subscribe to tagStore changes and return the result
  return useSyncExternalStore(tagStore.subscribe, getSnapshot, getSnapshot);
}

export function useTagActions() {
  return {
    createTag: tagStore.createTag.bind(tagStore),
    updateTag: tagStore.updateTag.bind(tagStore),
    deleteTag: tagStore.deleteTag.bind(tagStore),
    restoreTag: tagStore.restoreTag.bind(tagStore),
  };
}

export function useHabitTagActions() {
  return {
    addTagToHabit: habitTagStore.addTagToHabit.bind(habitTagStore),
    removeTagFromHabit: habitTagStore.removeTagFromHabit.bind(habitTagStore),
  };
}

// ============ Reward Hooks ============

/**
 * Subscribe to all rewards for a user.
 * Only re-renders when the reward list changes.
 */
export function useRewards(userId: string): Reward[] {
  const cacheRef = useRef<{ rewards: Reward[]; serialized: string }>({
    rewards: [],
    serialized: "[]",
  });

  const getSnapshotWithCache = useCallback(() => {
    const rewards = rewardStore.getAllRewards(userId);
    const serialized = JSON.stringify(
      rewards.map((r) => `${r.id}:${r.updated_at}`),
    );

    if (serialized !== cacheRef.current.serialized) {
      cacheRef.current = { rewards, serialized };
    }
    return cacheRef.current.rewards;
  }, [userId]);

  return useSyncExternalStore(
    rewardStore.subscribe,
    getSnapshotWithCache,
    getSnapshotWithCache,
  );
}

/**
 * Subscribe to a single reward by ID.
 * Only re-renders when THIS specific reward changes.
 */
export function useReward(rewardId: string): Reward | undefined {
  const cacheRef = useRef<{ reward: Reward | undefined; updatedAt: string }>({
    reward: undefined,
    updatedAt: "",
  });

  const getSnapshotWithCache = useCallback(() => {
    const reward = rewardStore.getRewardById(rewardId);
    const updatedAt = reward?.updated_at ?? "";

    if (updatedAt !== cacheRef.current.updatedAt) {
      cacheRef.current = { reward, updatedAt };
    }
    return cacheRef.current.reward;
  }, [rewardId]);

  return useSyncExternalStore(
    rewardStore.subscribe,
    getSnapshotWithCache,
    getSnapshotWithCache,
  );
}

/**
 * Subscribe to rewards sorted by damage for a user.
 * Sorted from highest damage to lowest, with unranked rewards at the bottom.
 */
export function useRewardsSortedByDamage(userId: string): Reward[] {
  const cacheRef = useRef<{ rewards: Reward[]; serialized: string }>({
    rewards: [],
    serialized: "[]",
  });

  const getSnapshotWithCache = useCallback(() => {
    const rewards = rewardStore.getRewardsSortedByDamage(userId);
    const serialized = JSON.stringify(
      rewards.map((r) => `${r.id}:${r.updated_at}`),
    );

    if (serialized !== cacheRef.current.serialized) {
      cacheRef.current = { rewards, serialized };
    }
    return cacheRef.current.rewards;
  }, [userId]);

  return useSyncExternalStore(
    rewardStore.subscribe,
    getSnapshotWithCache,
    getSnapshotWithCache,
  );
}

export function useRewardActions() {
  return {
    createReward: rewardStore.createReward.bind(rewardStore),
    updateReward: rewardStore.updateReward.bind(rewardStore),
    deleteReward: rewardStore.deleteReward.bind(rewardStore),
    reload: rewardStore.reload.bind(rewardStore),
  };
}

// ============ Reward Tag Hooks ============

/**
 * Subscribe to tags for a specific reward.
 * Only re-renders when THIS reward's tags change.
 */
export function useTagsForReward(rewardId: string): Tag[] {
  const cacheRef = useRef<{ tags: Tag[]; serialized: string }>({
    tags: [],
    serialized: "[]",
  });

  const getSnapshot = useCallback(() => {
    const tagIds = rewardTagStore.getTagIdsForReward(rewardId);
    const tags = tagIds
      .map((id) => tagStore.getTagById(id))
      .filter((t): t is Tag => t != null && !t.deleted_at);

    const serialized = JSON.stringify(
      tags.map((t) => `${t.id}:${t.updated_at}`),
    );

    if (serialized !== cacheRef.current.serialized) {
      cacheRef.current = { tags, serialized };
    }
    return cacheRef.current.tags;
  }, [rewardId]);

  // Subscribe to rewardTagStore changes
  useSyncExternalStore(rewardTagStore.subscribe, getSnapshot, getSnapshot);

  // Subscribe to tagStore changes and return the result
  return useSyncExternalStore(tagStore.subscribe, getSnapshot, getSnapshot);
}

export function useRewardTagActions() {
  return {
    addTagToReward: rewardTagStore.addTagToReward.bind(rewardTagStore),
    removeTagFromReward: rewardTagStore.removeTagFromReward.bind(rewardTagStore),
  };
}

// ============ Trade Hooks ============

/**
 * Subscribe to all trades for a user.
 * Only re-renders when the trade list changes.
 */
export function useTrades(userId: string): Trade[] {
  const cacheRef = useRef<{ trades: Trade[]; serialized: string }>({
    trades: [],
    serialized: "[]",
  });

  const getSnapshotWithCache = useCallback(() => {
    const trades = tradeStore.getAllTrades(userId);
    const serialized = JSON.stringify(
      trades.map((t) => `${t.id}:${t.updated_at}`),
    );

    if (serialized !== cacheRef.current.serialized) {
      cacheRef.current = { trades, serialized };
    }
    return cacheRef.current.trades;
  }, [userId]);

  return useSyncExternalStore(
    tradeStore.subscribe,
    getSnapshotWithCache,
    getSnapshotWithCache,
  );
}
