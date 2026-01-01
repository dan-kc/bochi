import { Platform } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import type { Task, TaskInput } from "../task";
import { markTaskDirty } from "../sync/syncStorage";

const TASKS_STORAGE_KEY = "tofustash_tasks";

// ============ Types ============

interface TaskState {
  byId: Record<string, Task>;
  allIds: string[];
}

type Listener = () => void;

// ============ Storage Helpers ============

function readStorageSync(): TaskState {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    const data = localStorage.getItem(TASKS_STORAGE_KEY);
    const tasks: Task[] = data ? JSON.parse(data) : [];
    return normalize(tasks);
  }
  // For mobile or SSR, we'll load async and update
  return { byId: {}, allIds: [] };
}

async function readStorageAsync(): Promise<TaskState> {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    const data = localStorage.getItem(TASKS_STORAGE_KEY);
    const tasks: Task[] = data ? JSON.parse(data) : [];
    return normalize(tasks);
  } else {
    const data = await AsyncStorage.getItem(TASKS_STORAGE_KEY);
    const tasks: Task[] = data ? JSON.parse(data) : [];
    return normalize(tasks);
  }
}

async function writeStorage(state: TaskState): Promise<void> {
  const tasks = denormalize(state);
  const data = JSON.stringify(tasks);
  if (Platform.OS === "web" && typeof window !== "undefined") {
    localStorage.setItem(TASKS_STORAGE_KEY, data);
  } else {
    await AsyncStorage.setItem(TASKS_STORAGE_KEY, data);
  }
}

function normalize(tasks: Task[]): TaskState {
  const byId: Record<string, Task> = {};
  const allIds: string[] = [];
  for (const task of tasks) {
    byId[task.id] = task;
    allIds.push(task.id);
  }
  return { byId, allIds };
}

function denormalize(state: TaskState): Task[] {
  return state.allIds.map((id) => state.byId[id]);
}

// ============ Store Class ============

class TaskStore {
  private state: TaskState = { byId: {}, allIds: [] };
  private listeners = new Set<Listener>();
  private initialized = false;

  constructor() {
    // Initial sync load for web (client-side only)
    if (Platform.OS === "web" && typeof window !== "undefined") {
      this.state = readStorageSync();
      this.initialized = true;
      this.setupCrossTabSync();
    } else if (Platform.OS !== "web") {
      // Async load for mobile
      this.init();
    }
    // For SSR, we start with empty state and hydrate on client
  }

  private async init() {
    this.state = await readStorageAsync();
    this.initialized = true;
    this.notify();
  }

  private setupCrossTabSync() {
    if (Platform.OS !== "web" || typeof window === "undefined") return;

    window.addEventListener("storage", (e) => {
      if (e.key === TASKS_STORAGE_KEY && e.newValue) {
        const tasks: Task[] = JSON.parse(e.newValue);
        this.state = normalize(tasks);
        this.notify();
      }
    });
  }

  private notify() {
    for (const listener of this.listeners) {
      listener();
    }
  }

  // ============ useSyncExternalStore API ============

  subscribe = (listener: Listener): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  getSnapshot = (): TaskState => {
    return this.state;
  };

  getServerSnapshot = (): TaskState => {
    return this.state;
  };

  // ============ Selectors ============

  getAllTasks(userId: string): Task[] {
    return this.state.allIds
      .map((id) => this.state.byId[id])
      .filter((t) => t.user_id === userId && !t.deleted_at)
      .sort(
        (a, b) =>
          new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
      );
  }

  getTaskById(id: string): Task | undefined {
    return this.state.byId[id];
  }

  // ============ Mutations ============

  async createTask(userId: string, input: TaskInput): Promise<Task> {
    const now = new Date().toISOString();
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
    };

    // Update state
    this.state = {
      byId: { ...this.state.byId, [id]: task },
      allIds: [id, ...this.state.allIds],
    };

    // Persist and notify
    await writeStorage(this.state);
    await markTaskDirty(id);
    this.notify();

    return task;
  }

  async updateTask(
    id: string,
    input: Partial<TaskInput>,
  ): Promise<Task | null> {
    const existing = this.state.byId[id];
    if (!existing) return null;

    const now = new Date().toISOString();
    const updated: Task = {
      ...existing,
      name: input.name ?? existing.name,
      description: input.description ?? existing.description,
      deleted_at:
        input.deleted_at !== undefined ? input.deleted_at : existing.deleted_at,
      hidden_until:
        input.hidden_until !== undefined
          ? input.hidden_until
          : existing.hidden_until,
      due_by: input.due_by !== undefined ? input.due_by : existing.due_by,
      min_daily_frequency:
        input.min_daily_frequency !== undefined
          ? input.min_daily_frequency
          : existing.min_daily_frequency,
      updated_at: now,
    };

    // Update state
    this.state = {
      ...this.state,
      byId: { ...this.state.byId, [id]: updated },
    };

    // Persist and notify
    await writeStorage(this.state);
    await markTaskDirty(id);
    this.notify();

    return updated;
  }

  async deleteTask(id: string): Promise<boolean> {
    const existing = this.state.byId[id];
    if (!existing) return false;

    const now = new Date().toISOString();
    const updated: Task = {
      ...existing,
      deleted_at: now,
      updated_at: now,
    };

    // Update state
    this.state = {
      ...this.state,
      byId: { ...this.state.byId, [id]: updated },
    };

    // Persist and notify
    await writeStorage(this.state);
    await markTaskDirty(id);
    this.notify();

    return true;
  }

  // ============ Sync Helpers ============

  async mergeTasks(serverTasks: Task[]): Promise<void> {
    const newById = { ...this.state.byId };
    const existingIds = new Set(this.state.allIds);

    for (const task of serverTasks) {
      newById[task.id] = task;
      if (!existingIds.has(task.id)) {
        existingIds.add(task.id);
      }
    }

    this.state = {
      byId: newById,
      allIds: Array.from(existingIds),
    };

    await writeStorage(this.state);
    this.notify();
  }

  async purgeDeletedTasks(): Promise<void> {
    const activeIds = this.state.allIds.filter(
      (id) => this.state.byId[id].deleted_at === null,
    );
    const activeById: Record<string, Task> = {};
    for (const id of activeIds) {
      activeById[id] = this.state.byId[id];
    }

    this.state = { byId: activeById, allIds: activeIds };
    await writeStorage(this.state);
    this.notify();
  }

  getDirtyTasks(dirtyIds: Set<string>): Task[] {
    return Array.from(dirtyIds)
      .map((id) => this.state.byId[id])
      .filter(Boolean);
  }

  async reload(): Promise<void> {
    this.state = await readStorageAsync();
    this.notify();
  }
}

// ============ Utilities ============

function generateUUID(): string {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

// ============ Singleton Export ============

export const taskStore = new TaskStore();
