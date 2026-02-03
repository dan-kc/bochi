import type { Habit, HabitInput } from "../habit";
import { markHabitDirty, markHabitsDirty } from "../sync/syncStorage";
import { EntityStore, generateUUID } from "./createStore";

const HABITS_STORAGE_KEY = "tofustash_habits";

// User ID used when offline (no authenticated user)
export const LOCAL_USER_ID = "local-user";

// ============ Habit Normalization ============

export function normalizeHabit(habit: Partial<Habit>): Habit {
  return {
    id: habit.id ?? "",
    user_id: habit.user_id ?? "",
    name: habit.name ?? "",
    description: habit.description ?? "",
    created_at: habit.created_at ?? new Date().toISOString(),
    updated_at: habit.updated_at ?? new Date().toISOString(),
    deleted_at: habit.deleted_at ?? null,
    hidden_until: habit.hidden_until ?? null,
    min_daily_frequency: habit.min_daily_frequency ?? null,
    difficulty_rank: habit.difficulty_rank ?? null,
  };
}

// ============ Habit Store ============

class HabitStore extends EntityStore<Habit> {
  constructor() {
    super({
      storageKey: HABITS_STORAGE_KEY,
      normalize: normalizeHabit,
      markDirty: markHabitDirty,
      markManyDirty: markHabitsDirty,
      enableVisibilityReload: true,
      enableAppStateReload: true,
    });
  }

  // ============ Habit-specific Selectors ============

  getAllHabits(userId: string): Habit[] {
    return this.getAll(userId);
  }

  getHabitsSortedByDifficulty(userId: string): Habit[] {
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

  getHabitById(id: string): Habit | undefined {
    return this.getById(id);
  }

  getHabitCount(userId: string): number {
    return this.state.allIds.filter(
      (id) => this.state.byId[id].user_id === userId && !this.state.byId[id].deleted_at,
    ).length;
  }

  // ============ Habit Mutations ============

  async createHabit(userId: string, input: HabitInput): Promise<Habit> {
    const now = new Date().toISOString();
    const habit: Habit = {
      id: generateUUID(),
      user_id: userId,
      name: input.name,
      description: input.description,
      created_at: now,
      updated_at: now,
      deleted_at: input.deleted_at ?? null,
      hidden_until: input.hidden_until ?? null,
      min_daily_frequency: input.min_daily_frequency ?? null,
      difficulty_rank: input.difficulty_rank ?? null,
    };

    await this.addItem(habit);
    return habit;
  }

  async updateHabit(id: string, input: Partial<HabitInput>): Promise<Habit | null> {
    const existing = this.state.byId[id];
    if (!existing) return null;

    const updates: Partial<Habit> = {};
    if (input.name !== undefined) updates.name = input.name;
    if (input.description !== undefined) updates.description = input.description;
    if (input.deleted_at !== undefined) updates.deleted_at = input.deleted_at;
    if (input.hidden_until !== undefined) updates.hidden_until = input.hidden_until;
    if (input.min_daily_frequency !== undefined) updates.min_daily_frequency = input.min_daily_frequency;
    if (input.difficulty_rank !== undefined) updates.difficulty_rank = input.difficulty_rank;

    return this.updateItem(id, updates);
  }

  async deleteHabit(id: string): Promise<boolean> {
    const result = await this.updateItem(id, { deleted_at: new Date().toISOString() });
    return result !== null;
  }

  // ============ Sync Helpers (aliases for compatibility) ============

  async mergeHabits(serverHabits: Partial<Habit>[], userId?: string): Promise<void> {
    return this.merge(serverHabits, userId);
  }

  getDirtyHabits(dirtyIds: Set<string>): Habit[] {
    return this.getDirty(dirtyIds);
  }

  async purgeDeletedHabits(): Promise<void> {
    return this.purgeDeleted();
  }

  async clearAllHabits(): Promise<void> {
    return this.clearAll();
  }

  async updateAllHabitsUserId(newUserId: string, fromUserId?: string): Promise<string[]> {
    return this.updateAllUserId(newUserId, fromUserId);
  }

  async migrateLocalUserHabits(newUserId: string): Promise<number> {
    const migratedIds = await this.updateAllUserId(newUserId, LOCAL_USER_ID);
    if (migratedIds.length > 0) {
      console.log(`[HabitStore] Migrated ${migratedIds.length} habits from local-user to ${newUserId}`);
    }
    return migratedIds.length;
  }
}

// ============ Singleton Export ============

export const habitStore = new HabitStore();
