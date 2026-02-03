import { describe, test, expect } from "vitest";
import { normalizeHabit } from "./habitStore";
import type { Habit } from "../habit";

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
      expect(result.hidden_until).toBeNull();
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
        hidden_until: "2024-07-01T00:00:00Z",
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
