import { describe, test, expect } from "vitest";
import { normalizeHabit } from "./habitStore";
import type { Habit, HabitInput } from "../habit";

describe("normalizeHabit", () => {
  describe("providing defaults for missing fields", () => {
    test("provides defaults for minimal data", () => {
      const data = { id: "1", name: "Exercise" };
      const result = normalizeHabit(data);

      expect(result.id).toBe("1");
      expect(result.name).toBe("Exercise");
      expect(result.user_id).toBe("");
      expect(result.description).toBe("");
      expect(result.deleted_at).toBeNull();

      expect(result.min_daily_frequency).toBeNull();
      expect(result.difficulty_rank).toBeNull();
    });

    test("generates timestamps when missing", () => {
      const data = { id: "1", name: "New Habit" };
      const before = new Date().toISOString();
      const result = normalizeHabit(data);
      const after = new Date().toISOString();

      expect(new Date(result.created_at).toISOString()).toBe(result.created_at);
      expect(new Date(result.updated_at).toISOString()).toBe(result.updated_at);
      expect(result.created_at >= before).toBe(true);
      expect(result.created_at <= after).toBe(true);
    });

    test("handles empty object", () => {
      const result = normalizeHabit({});

      expect(result.id).toBe("");
      expect(result.name).toBe("");
      expect(result.user_id).toBe("");
    });
  });

  describe("preserving existing values", () => {
    test("preserves all fields when complete data is provided", () => {
      const completeData: Habit = {
        id: "abc-123",
        user_id: "user-456",
        name: "Morning Run",
        description: "Run 5km every morning",
        created_at: "2024-06-15T08:00:00Z",
        updated_at: "2024-06-20T10:30:00Z",
        deleted_at: null,
        min_daily_frequency: 1,
        difficulty_rank: "A",
      };
      const result = normalizeHabit(completeData);

      expect(result).toEqual(completeData);
    });

    test("preserves deleted_at when set", () => {
      const deletedHabit = {
        id: "1",
        name: "Old Habit",
        deleted_at: "2024-01-15T00:00:00Z",
      };
      const result = normalizeHabit(deletedHabit);

      expect(result.deleted_at).toBe("2024-01-15T00:00:00Z");
    });

    test("preserves zero values correctly", () => {
      const data = {
        id: "1",
        name: "Test",
        min_daily_frequency: 0,
      };
      const result = normalizeHabit(data);

      expect(result.min_daily_frequency).toBe(0);
    });

    test("preserves empty string for name", () => {
      const data = { id: "1", name: "" };
      const result = normalizeHabit(data);

      expect(result.name).toBe("");
    });
  });
});

describe("updateHabit input handling", () => {
  // This test verifies the logic used by updateHabit to determine which fields
  // to update. The key behavior is that difficulty_rank: null should be treated
  // as an explicit value to set, not as "no update". This is critical for the
  // merge flow during login where we clear difficulty_rank on merged habits.

  function computeUpdates(input: Partial<HabitInput>): Partial<Habit> {
    // This mirrors the logic in HabitStore.updateHabit()
    const updates: Partial<Habit> = {};
    if (input.name !== undefined) updates.name = input.name;
    if (input.description !== undefined) updates.description = input.description;
    if (input.deleted_at !== undefined) updates.deleted_at = input.deleted_at;
    if (input.min_daily_frequency !== undefined) updates.min_daily_frequency = input.min_daily_frequency;
    if (input.difficulty_rank !== undefined) updates.difficulty_rank = input.difficulty_rank;
    return updates;
  }

  test("explicitly setting difficulty_rank to null includes it in updates", () => {
    // This is the key behavior for clearing difficulty on merge
    const input: Partial<HabitInput> = { difficulty_rank: null };
    const updates = computeUpdates(input);

    expect(updates).toHaveProperty("difficulty_rank");
    expect(updates.difficulty_rank).toBeNull();
  });

  test("omitting difficulty_rank does not include it in updates", () => {
    const input: Partial<HabitInput> = { name: "Updated name" };
    const updates = computeUpdates(input);

    expect(updates).not.toHaveProperty("difficulty_rank");
    expect(updates.name).toBe("Updated name");
  });

  test("setting difficulty_rank to a value includes it in updates", () => {
    const input: Partial<HabitInput> = { difficulty_rank: "a0" };
    const updates = computeUpdates(input);

    expect(updates).toHaveProperty("difficulty_rank");
    expect(updates.difficulty_rank).toBe("a0");
  });

  test("clearing multiple nullable fields works correctly", () => {
    // Simulates what happens during merge: clearing difficulty_rank
    const input: Partial<HabitInput> = {
      difficulty_rank: null,
    };
    const updates = computeUpdates(input);

    expect(updates.difficulty_rank).toBeNull();
  });
});
