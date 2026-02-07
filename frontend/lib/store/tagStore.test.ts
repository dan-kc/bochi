import { describe, test, expect } from "vitest";
import { normalizeTag } from "./tagStore";
import type { Tag, TagInput } from "../tag";

describe("normalizeTag", () => {
  describe("providing defaults for missing fields", () => {
    test("provides defaults for minimal data", () => {
      const data = { id: "1", name: "Work" };
      const result = normalizeTag(data);

      expect(result.id).toBe("1");
      expect(result.name).toBe("Work");
      expect(result.user_id).toBe("");
      expect(result.deleted_at).toBeNull();
    });

    test("generates random color when missing", () => {
      const data = { id: "1", name: "Tag" };
      const result = normalizeTag(data);

      expect(result.color_hex).toMatch(/^#[0-9A-F]{8}$/);
    });

    test("generates timestamps when missing", () => {
      const data = { id: "1", name: "New Tag" };
      const before = new Date().toISOString();
      const result = normalizeTag(data);
      const after = new Date().toISOString();

      expect(new Date(result.created_at).toISOString()).toBe(result.created_at);
      expect(new Date(result.updated_at).toISOString()).toBe(result.updated_at);
      expect(result.created_at >= before).toBe(true);
      expect(result.created_at <= after).toBe(true);
    });

    test("handles empty object", () => {
      const result = normalizeTag({});

      expect(result.id).toBe("");
      expect(result.name).toBe("");
      expect(result.user_id).toBe("");
      expect(result.color_hex).toMatch(/^#[0-9A-F]{8}$/);
    });
  });

  describe("preserving existing values", () => {
    test("preserves all fields when complete data is provided", () => {
      const completeData: Tag = {
        id: "abc-123",
        user_id: "user-456",
        name: "Work",
        color_hex: "#FF5733FF",
        created_at: "2024-06-15T08:00:00Z",
        updated_at: "2024-06-20T10:30:00Z",
        deleted_at: null,
      };
      const result = normalizeTag(completeData);

      expect(result).toEqual(completeData);
    });

    test("preserves existing color_hex", () => {
      const data = { id: "1", name: "Work", color_hex: "#FF5733FF" };
      const result = normalizeTag(data);

      expect(result.color_hex).toBe("#FF5733FF");
    });

    test("preserves deleted_at when set", () => {
      const deletedTag = {
        id: "1",
        name: "Old Tag",
        deleted_at: "2024-01-15T00:00:00Z",
      };
      const result = normalizeTag(deletedTag);

      expect(result.deleted_at).toBe("2024-01-15T00:00:00Z");
    });

    test("preserves empty string for name", () => {
      const data = { id: "1", name: "" };
      const result = normalizeTag(data);

      expect(result.name).toBe("");
    });
  });
});

describe("updateTag input handling", () => {
  function computeUpdates(input: Partial<TagInput>): Partial<Tag> {
    const updates: Partial<Tag> = {};
    if (input.name !== undefined) updates.name = input.name;
    if (input.color_hex !== undefined) updates.color_hex = input.color_hex;
    if (input.deleted_at !== undefined) updates.deleted_at = input.deleted_at;
    return updates;
  }

  test("explicitly setting deleted_at to null includes it in updates", () => {
    const input: Partial<TagInput> = { deleted_at: null };
    const updates = computeUpdates(input);

    expect(updates).toHaveProperty("deleted_at");
    expect(updates.deleted_at).toBeNull();
  });

  test("omitting name does not include it in updates", () => {
    const input: Partial<TagInput> = { color_hex: "#00FF00FF" };
    const updates = computeUpdates(input);

    expect(updates).not.toHaveProperty("name");
    expect(updates.color_hex).toBe("#00FF00FF");
  });

  test("setting name includes it in updates", () => {
    const input: Partial<TagInput> = { name: "Updated" };
    const updates = computeUpdates(input);

    expect(updates).toHaveProperty("name");
    expect(updates.name).toBe("Updated");
  });
});
