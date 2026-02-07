import { describe, test, expect } from "vitest";
import { normalizeHabitTag } from "./habitTagStore";
import type { HabitTag } from "../habitTag";

describe("normalizeHabitTag", () => {
  describe("providing defaults for missing fields", () => {
    test("provides defaults for minimal data", () => {
      const data = { habit_id: "h1", tag_id: "t1" };
      const result = normalizeHabitTag(data);

      expect(result.habit_id).toBe("h1");
      expect(result.tag_id).toBe("t1");
      expect(result.user_id).toBe("");
      expect(result.deleted_at).toBeNull();
    });

    test("generates timestamps when missing", () => {
      const data = { habit_id: "h1", tag_id: "t1" };
      const before = new Date().toISOString();
      const result = normalizeHabitTag(data);
      const after = new Date().toISOString();

      expect(new Date(result.created_at).toISOString()).toBe(result.created_at);
      expect(new Date(result.updated_at).toISOString()).toBe(result.updated_at);
      expect(result.created_at >= before).toBe(true);
      expect(result.created_at <= after).toBe(true);
    });

    test("handles empty object", () => {
      const result = normalizeHabitTag({});

      expect(result.habit_id).toBe("");
      expect(result.tag_id).toBe("");
      expect(result.user_id).toBe("");
    });
  });

  describe("preserving existing values", () => {
    test("preserves all fields when complete data is provided", () => {
      const completeData: HabitTag = {
        habit_id: "h-123",
        tag_id: "t-456",
        user_id: "user-789",
        created_at: "2024-06-15T08:00:00Z",
        updated_at: "2024-06-20T10:30:00Z",
        deleted_at: null,
      };
      const result = normalizeHabitTag(completeData);

      expect(result).toEqual(completeData);
    });

    test("preserves deleted_at when set", () => {
      const deletedAssociation = {
        habit_id: "h1",
        tag_id: "t1",
        deleted_at: "2024-01-15T00:00:00Z",
      };
      const result = normalizeHabitTag(deletedAssociation);

      expect(result.deleted_at).toBe("2024-01-15T00:00:00Z");
    });
  });
});
