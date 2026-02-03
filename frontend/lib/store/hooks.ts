import { useSyncExternalStore, useCallback, useRef } from "react";
import { habitStore } from "./habitStore";
import type { Habit } from "../habit";

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
