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

// ============ Cached Selector Helpers ============

function useCachedListSelector<T>(
  subscribe: (listener: () => void) => () => void,
  selector: () => T[],
  serialize: (items: T[]) => string,
): T[] {
  const cacheRef = useRef<{ items: T[]; serialized: string }>({
    items: [],
    serialized: "[]",
  });

  const getSnapshot = useCallback(() => {
    const items = selector();
    const serialized = serialize(items);
    if (serialized !== cacheRef.current.serialized) {
      cacheRef.current = { items, serialized };
    }
    return cacheRef.current.items;
  }, [selector, serialize]);

  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

function useCachedItemSelector<T extends { updated_at?: string }>(
  subscribe: (listener: () => void) => () => void,
  selector: () => T | undefined,
): T | undefined {
  const cacheRef = useRef<{ item: T | undefined; updatedAt: string }>({
    item: undefined,
    updatedAt: "",
  });

  const getSnapshot = useCallback(() => {
    const item = selector();
    const updatedAt = item?.updated_at ?? "";
    if (updatedAt !== cacheRef.current.updatedAt) {
      cacheRef.current = { item, updatedAt };
    }
    return cacheRef.current.item;
  }, [selector]);

  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

function serializeByIdAndUpdatedAt(items: { id: string; updated_at: string }[]): string {
  return JSON.stringify(items.map((i) => `${i.id}:${i.updated_at}`));
}

function serializeByIdUpdatedDeleted(items: { id: string; updated_at: string; deleted_at: string | null }[]): string {
  return JSON.stringify(items.map((i) => `${i.id}:${i.updated_at}:${i.deleted_at ?? ""}`));
}

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

// ============ Habit Hooks ============

/**
 * Subscribe to all habits for a user (filtered, sorted).
 * Only re-renders when the filtered list changes.
 */
export function useHabits(userId: string): Habit[] {
  const selector = useCallback(() => habitStore.getAllHabits(userId), [userId]);
  return useCachedListSelector(habitStore.subscribe, selector, serializeByIdAndUpdatedAt);
}

/**
 * Subscribe to a single habit by ID.
 * Only re-renders when THIS specific habit changes.
 */
export function useHabit(habitId: string): Habit | undefined {
  const selector = useCallback(() => habitStore.getHabitById(habitId), [habitId]);
  return useCachedItemSelector(habitStore.subscribe, selector);
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
  const selector = useCallback(() => habitStore.getHabitsSortedByDifficulty(userId), [userId]);
  return useCachedListSelector(habitStore.subscribe, selector, serializeByIdAndUpdatedAt);
}

// ============ Habit Actions ============

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
  const selector = useCallback(() => tagStore.getAllTags(userId), [userId]);
  return useCachedListSelector(tagStore.subscribe, selector, serializeByIdAndUpdatedAt);
}

/**
 * Subscribe to all tags including deleted ones for a user.
 * Useful for tag selection modal with restore option.
 */
export function useAllTagsIncludingDeleted(userId: string): Tag[] {
  const selector = useCallback(() => tagStore.getAllTagsIncludingDeleted(userId), [userId]);
  return useCachedListSelector(tagStore.subscribe, selector, serializeByIdUpdatedDeleted);
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

  const getSnapshot = useCallback(() => {
    const tagIds = habitTagStore.getTagIdsForHabit(habitId);
    const tags = tagIds
      .map((id) => tagStore.getTagById(id))
      .filter((t): t is Tag => t != null && !t.deleted_at);

    const serialized = serializeByIdAndUpdatedAt(tags);

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
  const selector = useCallback(() => rewardStore.getAllRewards(userId), [userId]);
  return useCachedListSelector(rewardStore.subscribe, selector, serializeByIdAndUpdatedAt);
}

/**
 * Subscribe to a single reward by ID.
 * Only re-renders when THIS specific reward changes.
 */
export function useReward(rewardId: string): Reward | undefined {
  const selector = useCallback(() => rewardStore.getRewardById(rewardId), [rewardId]);
  return useCachedItemSelector(rewardStore.subscribe, selector);
}

/**
 * Subscribe to rewards sorted by damage for a user.
 * Sorted from highest damage to lowest, with unranked rewards at the bottom.
 */
export function useRewardsSortedByDamage(userId: string): Reward[] {
  const selector = useCallback(() => rewardStore.getRewardsSortedByDamage(userId), [userId]);
  return useCachedListSelector(rewardStore.subscribe, selector, serializeByIdAndUpdatedAt);
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

    const serialized = serializeByIdAndUpdatedAt(tags);

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
  const selector = useCallback(() => tradeStore.getAllTrades(userId), [userId]);
  return useCachedListSelector(tradeStore.subscribe, selector, serializeByIdAndUpdatedAt);
}
