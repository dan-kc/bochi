import type { HabitTag } from "../habitTag";
import { habitTagKey } from "../habitTag";
import { markHabitTagDirty, markHabitTagsDirty } from "../sync/syncStorage";
import { CompositeKeyStore } from "./createCompositeKeyStore";

export function normalizeHabitTag(ht: Partial<HabitTag>): HabitTag {
  return {
    habit_id: ht.habit_id ?? "",
    tag_id: ht.tag_id ?? "",
    user_id: ht.user_id ?? "",
    created_at: ht.created_at ?? new Date().toISOString(),
    updated_at: ht.updated_at ?? new Date().toISOString(),
    deleted_at: ht.deleted_at ?? null,
  };
}

class HabitTagStore extends CompositeKeyStore<HabitTag> {
  constructor() {
    super({
      storageKey: "tofustash_habit_tags",
      normalize: normalizeHabitTag,
      getKey: (ht) => habitTagKey(ht.habit_id, ht.tag_id),
      markDirty: markHabitTagDirty,
      markManyDirty: markHabitTagsDirty,
    });
  }

  getTagIdsForHabit(habitId: string): string[] {
    return this.getIdsForField("habit_id", habitId, "tag_id");
  }

  getHabitIdsForTag(tagId: string): string[] {
    return this.getIdsForField("tag_id", tagId, "habit_id");
  }

  async addTagToHabit(userId: string, habitId: string, tagId: string): Promise<HabitTag> {
    const now = new Date().toISOString();
    return this.addItem({
      habit_id: habitId,
      tag_id: tagId,
      user_id: userId,
      created_at: now,
      updated_at: now,
      deleted_at: null,
    });
  }

  async removeTagFromHabit(habitId: string, tagId: string): Promise<boolean> {
    const key = habitTagKey(habitId, tagId);
    return this.removeItem(key, {} as HabitTag);
  }
}

export const habitTagStore = new HabitTagStore();
