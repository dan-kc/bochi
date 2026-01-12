import type { Task, TaskInput } from "../task";
import { markTaskDirty, markTasksDirty } from "../sync/syncStorage";
import { EntityStore, generateUUID } from "./createStore";

const TASKS_STORAGE_KEY = "tofustash_tasks";

// User ID used when offline (no authenticated user)
export const LOCAL_USER_ID = "local-user";

// ============ Task Normalization ============

function normalizeTask(task: Partial<Task>): Task {
  return {
    id: task.id ?? "",
    user_id: task.user_id ?? "",
    name: task.name ?? "",
    description: task.description ?? "",
    created_at: task.created_at ?? new Date().toISOString(),
    updated_at: task.updated_at ?? new Date().toISOString(),
    deleted_at: task.deleted_at ?? null,
    hidden_until: task.hidden_until ?? null,
    due_by: task.due_by ?? null,
    min_daily_frequency: task.min_daily_frequency ?? null,
    difficulty_rank: task.difficulty_rank ?? null,
    completed_at: task.completed_at ?? null,
    habit: task.habit ?? false,
  };
}

// ============ Task Store ============

class TaskStore extends EntityStore<Task> {
  constructor() {
    super({
      storageKey: TASKS_STORAGE_KEY,
      normalize: normalizeTask,
      markDirty: markTaskDirty,
      markManyDirty: markTasksDirty,
      enableVisibilityReload: true,
      enableAppStateReload: true,
    });
  }

  // ============ Task-specific Selectors ============

  getAllTasks(userId: string): Task[] {
    return this.getAll(userId);
  }

  getTasksSortedByDifficulty(userId: string): Task[] {
    return this.state.allIds
      .map((id) => this.state.byId[id])
      .filter((t) => t.user_id === userId && !t.deleted_at)
      .sort((a, b) => {
        if (a.difficulty_rank == null && b.difficulty_rank == null) return 0;
        if (a.difficulty_rank == null) return 1;
        if (b.difficulty_rank == null) return -1;
        return b.difficulty_rank.localeCompare(a.difficulty_rank);
      });
  }

  getTaskById(id: string): Task | undefined {
    return this.getById(id);
  }

  getTaskCount(userId: string): number {
    return this.state.allIds.filter(
      (id) => this.state.byId[id].user_id === userId && !this.state.byId[id].deleted_at,
    ).length;
  }

  // ============ Task Mutations ============

  async createTask(userId: string, input: TaskInput): Promise<Task> {
    const now = new Date().toISOString();
    const task: Task = {
      id: generateUUID(),
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

    await this.addItem(task);
    return task;
  }

  async updateTask(id: string, input: Partial<TaskInput>): Promise<Task | null> {
    const existing = this.state.byId[id];
    if (!existing) return null;

    const updates: Partial<Task> = {};
    if (input.name !== undefined) updates.name = input.name;
    if (input.description !== undefined) updates.description = input.description;
    if (input.deleted_at !== undefined) updates.deleted_at = input.deleted_at;
    if (input.hidden_until !== undefined) updates.hidden_until = input.hidden_until;
    if (input.due_by !== undefined) updates.due_by = input.due_by;
    if (input.min_daily_frequency !== undefined) updates.min_daily_frequency = input.min_daily_frequency;
    if (input.difficulty_rank !== undefined) updates.difficulty_rank = input.difficulty_rank;
    if (input.completed_at !== undefined) updates.completed_at = input.completed_at;
    if (input.habit !== undefined) updates.habit = input.habit;

    return this.updateItem(id, updates);
  }

  async deleteTask(id: string): Promise<boolean> {
    const result = await this.updateItem(id, { deleted_at: new Date().toISOString() });
    return result !== null;
  }

  // ============ Sync Helpers (aliases for compatibility) ============

  async mergeTasks(serverTasks: Partial<Task>[], userId?: string): Promise<void> {
    return this.merge(serverTasks, userId);
  }

  getDirtyTasks(dirtyIds: Set<string>): Task[] {
    return this.getDirty(dirtyIds);
  }

  async purgeDeletedTasks(): Promise<void> {
    return this.purgeDeleted();
  }

  async clearAllTasks(): Promise<void> {
    return this.clearAll();
  }

  async updateAllTasksUserId(newUserId: string, fromUserId?: string): Promise<string[]> {
    return this.updateAllUserId(newUserId, fromUserId);
  }

  async migrateLocalUserTasks(newUserId: string): Promise<number> {
    const migratedIds = await this.updateAllUserId(newUserId, LOCAL_USER_ID);
    if (migratedIds.length > 0) {
      console.log(`[TaskStore] Migrated ${migratedIds.length} tasks from local-user to ${newUserId}`);
    }
    return migratedIds.length;
  }
}

// ============ Singleton Export ============

export const taskStore = new TaskStore();
