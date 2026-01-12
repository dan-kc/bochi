import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import type { Task, TaskInput } from "./task";
import { markTaskDirty } from "./sync/syncStorage";

const TASKS_STORAGE_KEY = "tofustash_tasks";

// ============ Storage Helpers ============

async function getTasksFromStorage(): Promise<Task[]> {
  if (Platform.OS === "web") {
    const data = localStorage.getItem(TASKS_STORAGE_KEY);
    return data ? JSON.parse(data) : [];
  } else {
    const data = await AsyncStorage.getItem(TASKS_STORAGE_KEY);
    return data ? JSON.parse(data) : [];
  }
}

async function saveTasksToStorage(tasks: Task[]): Promise<void> {
  const data = JSON.stringify(tasks);
  if (Platform.OS === "web") {
    localStorage.setItem(TASKS_STORAGE_KEY, data);
  } else {
    await AsyncStorage.setItem(TASKS_STORAGE_KEY, data);
  }
}

// ============ Utility Functions ============

function generateUUID(): string {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

function getCurrentTimestamp(): string {
  return new Date().toISOString();
}

// ============ Public API ============

export async function getAllTasks(userId: string): Promise<Task[]> {
  const tasks = await getTasksFromStorage();
  return tasks
    .filter((t) => t.user_id === userId && !t.deleted_at)
    .sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
    );
}

export async function getTaskById(id: string): Promise<Task | null> {
  const tasks = await getTasksFromStorage();
  return tasks.find((t) => t.id === id) ?? null;
}

export async function createTask(
  userId: string,
  input: TaskInput,
): Promise<Task> {
  const now = getCurrentTimestamp();
  const id = generateUUID();

  const task: Task = {
    id,
    user_id: userId,
    name: input.name,
    description: input.description,
    created_at: now,
    updated_at: now,
    deleted_at: input.deleted_at ?? null,
    hidden_until: input.hidden_until ?? null,
    due_by: input.due_by ?? null,
    min_daily_frequency: input.min_daily_frequency ?? null,
    difficulty_rank: input.difficulty_rank ?? null,
    completed_at: input.completed_at ?? null,
    habit: input.habit,
  };

  const tasks = await getTasksFromStorage();
  tasks.push(task);
  await saveTasksToStorage(tasks);
  await markTaskDirty(task.id);

  return task;
}

export async function updateTask(
  id: string,
  input: Partial<TaskInput>,
): Promise<Task | null> {
  const tasks = await getTasksFromStorage();
  const index = tasks.findIndex((t) => t.id === id);

  if (index === -1) {
    return null;
  }

  const existingTask = tasks[index];
  const now = getCurrentTimestamp();

  const updatedTask: Task = {
    ...existingTask,
    name: input.name ?? existingTask.name,
    description: input.description ?? existingTask.description,
    deleted_at:
      input.deleted_at !== undefined
        ? input.deleted_at
        : existingTask.deleted_at,
    hidden_until:
      input.hidden_until !== undefined
        ? input.hidden_until
        : existingTask.hidden_until,
    due_by: input.due_by !== undefined ? input.due_by : existingTask.due_by,
    min_daily_frequency:
      input.min_daily_frequency !== undefined
        ? input.min_daily_frequency
        : existingTask.min_daily_frequency,
    completed_at:
      input.completed_at !== undefined
        ? input.completed_at
        : existingTask.completed_at,
    updated_at: now,
  };

  tasks[index] = updatedTask;
  await saveTasksToStorage(tasks);
  await markTaskDirty(updatedTask.id);

  return updatedTask;
}

export async function deleteTask(id: string): Promise<boolean> {
  const tasks = await getTasksFromStorage();
  const index = tasks.findIndex((t) => t.id === id);

  if (index === -1) {
    return false;
  }

  const now = getCurrentTimestamp();
  tasks[index] = {
    ...tasks[index],
    deleted_at: now,
    updated_at: now,
  };

  await saveTasksToStorage(tasks);
  await markTaskDirty(id);
  return true;
}

// ============ Sync Helpers ============

export async function getAllTasksRaw(): Promise<Task[]> {
  return getTasksFromStorage();
}

export async function getDirtyTasks(dirtyIds: Set<string>): Promise<Task[]> {
  const tasks = await getTasksFromStorage();
  return tasks.filter((t) => dirtyIds.has(t.id));
}

export async function mergeTasks(serverTasks: Task[]): Promise<void> {
  const localTasks = await getTasksFromStorage();
  const localTaskMap = new Map(localTasks.map((t) => [t.id, t]));

  for (const serverTask of serverTasks) {
    localTaskMap.set(serverTask.id, serverTask);
  }

  await saveTasksToStorage(Array.from(localTaskMap.values()));
}

export async function purgeDeletedTasks(): Promise<void> {
  const tasks = await getTasksFromStorage();
  const activeTasks = tasks.filter((t) => t.deleted_at === null);
  await saveTasksToStorage(activeTasks);
}
