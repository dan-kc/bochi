import { useSyncExternalStore, useCallback, useRef } from "react";
import { taskStore } from "./taskStore";
import type { Task } from "../task";

// ============ Core Subscription Hook ============

/**
 * Subscribe to the entire task state.
 * Re-renders on ANY task change.
 */
export function useTaskStore() {
  return useSyncExternalStore(
    taskStore.subscribe,
    taskStore.getSnapshot,
    taskStore.getServerSnapshot,
  );
}

// ============ Fine-Grained Hooks ============

/**
 * Subscribe to all tasks for a user (filtered, sorted).
 * Only re-renders when the filtered list changes.
 */
export function useTasks(userId: string): Task[] {
  const getSnapshot = useCallback(() => {
    return taskStore.getAllTasks(userId);
  }, [userId]);

  // Use a ref to cache the previous result for shallow comparison
  const cacheRef = useRef<{ tasks: Task[]; serialized: string }>({
    tasks: [],
    serialized: "[]",
  });

  const getSnapshotWithCache = useCallback(() => {
    const tasks = taskStore.getAllTasks(userId);
    // Serialize for comparison (only IDs and updated_at for efficiency)
    const serialized = JSON.stringify(
      tasks.map((t) => `${t.id}:${t.updated_at}`),
    );

    if (serialized !== cacheRef.current.serialized) {
      cacheRef.current = { tasks, serialized };
    }
    return cacheRef.current.tasks;
  }, [userId]);

  return useSyncExternalStore(
    taskStore.subscribe,
    getSnapshotWithCache,
    getSnapshotWithCache,
  );
}

/**
 * Subscribe to a single task by ID.
 * Only re-renders when THIS specific task changes.
 */
export function useTask(taskId: string): Task | undefined {
  const getSnapshot = useCallback(() => {
    return taskStore.getTaskById(taskId);
  }, [taskId]);

  // Cache to prevent unnecessary re-renders
  const cacheRef = useRef<{ task: Task | undefined; updatedAt: string }>({
    task: undefined,
    updatedAt: "",
  });

  const getSnapshotWithCache = useCallback(() => {
    const task = taskStore.getTaskById(taskId);
    const updatedAt = task?.updated_at ?? "";

    if (updatedAt !== cacheRef.current.updatedAt) {
      cacheRef.current = { task, updatedAt };
    }
    return cacheRef.current.task;
  }, [taskId]);

  return useSyncExternalStore(
    taskStore.subscribe,
    getSnapshotWithCache,
    getSnapshotWithCache,
  );
}

/**
 * Subscribe to task count for a user.
 * Only re-renders when count changes.
 */
export function useTaskCount(userId: string): number {
  const getSnapshot = useCallback(() => {
    return taskStore.getAllTasks(userId).length;
  }, [userId]);

  return useSyncExternalStore(taskStore.subscribe, getSnapshot, getSnapshot);
}

// ============ Actions (no subscription, just mutations) ============

export function useTaskActions() {
  return {
    createTask: taskStore.createTask.bind(taskStore),
    updateTask: taskStore.updateTask.bind(taskStore),
    deleteTask: taskStore.deleteTask.bind(taskStore),
    reload: taskStore.reload.bind(taskStore),
  };
}
