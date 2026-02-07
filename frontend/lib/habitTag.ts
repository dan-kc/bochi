export interface HabitTag {
  habit_id: string;
  tag_id: string;
  user_id: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface HabitTagInput {
  habit_id: string;
  tag_id: string;
  deleted_at?: string | null;
}

/**
 * Creates a composite key for a habit-tag association
 */
export function habitTagKey(habitId: string, tagId: string): string {
  return `${habitId}:${tagId}`;
}

/**
 * Parses a composite key back into habit_id and tag_id
 */
export function parseHabitTagKey(key: string): { habitId: string; tagId: string } {
  const [habitId, tagId] = key.split(":");
  return { habitId, tagId };
}
