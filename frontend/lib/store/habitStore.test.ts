import { describe, test, expect } from "vitest";
import { normalizeHabit } from "./habitStore";
import type { Habit } from "../habit";

describe("normalizeHabit", () => {
  describe("migration from old schemas", () => {
    test("handles minimal data (v1 migration - only id and name)", () => {
      const oldData = { id: "1", name: "Exercise" };
      const result = normalizeHabit(oldData);

      expect(result.id).toBe("1");
      expect(result.name).toBe("Exercise");
      expect(result.user_id).toBe("");
      expect(result.description).toBe("");
      expect(result.deleted_at).toBeNull();
      expect(result.hidden_until).toBeNull();
      expect(result.min_daily_frequency).toBeNull();
      expect(result.difficulty_rank).toBeNull();
    });

    test("handles missing hidden_until field (added later)", () => {
      const oldData = {
        id: "1",
        user_id: "u1",
        name: "Read",
        description: "Read a book",
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        deleted_at: null,
      };
      const result = normalizeHabit(oldData);

      expect(result.hidden_until).toBeNull();
      expect(result.min_daily_frequency).toBeNull();
      expect(result.difficulty_rank).toBeNull();
    });

    test("handles missing difficulty_rank field", () => {
      const oldData = {
        id: "1",
        user_id: "u1",
        name: "Meditate",
        description: "",
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        deleted_at: null,
        hidden_until: null,
        min_daily_frequency: 1,
      };
      const result = normalizeHabit(oldData);

      expect(result.difficulty_rank).toBeNull();
      expect(result.min_daily_frequency).toBe(1);
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
      // Ensure 0 is not treated as falsy and replaced with default
      const data = {
        id: "1",
        name: "Test",
        min_daily_frequency: 0,
      };
      const result = normalizeHabit(data);

      // 0 is falsy, so ?? will use 0 (correct behavior)
      expect(result.min_daily_frequency).toBe(0);
    });

    test("preserves empty string for name", () => {
      const data = { id: "1", name: "" };
      const result = normalizeHabit(data);

      expect(result.name).toBe("");
    });
  });

  describe("edge cases", () => {
    test("handles empty object", () => {
      const result = normalizeHabit({});

      expect(result.id).toBe("");
      expect(result.name).toBe("");
      expect(result.user_id).toBe("");
    });

    test("generates timestamps for created_at and updated_at when missing", () => {
      const data = { id: "1", name: "New Habit" };
      const before = new Date().toISOString();
      const result = normalizeHabit(data);
      const after = new Date().toISOString();

      // Timestamps should be valid ISO strings
      expect(new Date(result.created_at).toISOString()).toBe(result.created_at);
      expect(new Date(result.updated_at).toISOString()).toBe(result.updated_at);

      // Should be approximately now
      expect(result.created_at >= before).toBe(true);
      expect(result.created_at <= after).toBe(true);
    });

    test("handles unknown extra fields gracefully", () => {
      const dataWithExtra = {
        id: "1",
        name: "Test",
        unknownField: "should be ignored",
        anotherExtra: 123,
      } as Partial<Habit>;
      const result = normalizeHabit(dataWithExtra);

      expect(result.id).toBe("1");
      expect(result.name).toBe("Test");
      // Extra fields should not appear in result (TypeScript enforces this)
      expect("unknownField" in result).toBe(false);
    });
  });
});
