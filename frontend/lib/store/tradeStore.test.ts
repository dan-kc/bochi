import { describe, test, expect } from "vitest";
import { normalizeTrade } from "./tradeStore";
import type { Trade } from "../trade";

describe("normalizeTrade", () => {
  describe("providing defaults for missing fields", () => {
    test("provides defaults for minimal data", () => {
      const data = { id: "1", amount: 100 };
      const result = normalizeTrade(data);

      expect(result.id).toBe("1");
      expect(result.amount).toBe(100);
      expect(result.user_id).toBe("");
      expect(result.habit_id).toBeNull();
      expect(result.reward_id).toBeNull();
      expect(result.deleted_at).toBeNull();
    });

    test("generates timestamps when missing", () => {
      const data = { id: "1", amount: 50 };
      const before = new Date().toISOString();
      const result = normalizeTrade(data);
      const after = new Date().toISOString();

      expect(new Date(result.created_at).toISOString()).toBe(result.created_at);
      expect(new Date(result.updated_at).toISOString()).toBe(result.updated_at);
      expect(result.created_at >= before).toBe(true);
      expect(result.created_at <= after).toBe(true);
    });

    test("handles empty object", () => {
      const result = normalizeTrade({});

      expect(result.id).toBe("");
      expect(result.user_id).toBe("");
      expect(result.amount).toBe(0);
    });
  });

  describe("preserving existing values", () => {
    test("preserves all fields when complete data is provided", () => {
      const completeData: Trade = {
        id: "trade-123",
        user_id: "user-456",
        habit_id: "habit-789",
        reward_id: null,
        amount: 100,
        created_at: "2024-06-15T08:00:00Z",
        updated_at: "2024-06-15T08:00:00Z",
        deleted_at: null,
      };
      const result = normalizeTrade(completeData);

      expect(result).toEqual(completeData);
    });

    test("preserves reward_id when set (spending soy)", () => {
      const spendTrade = {
        id: "1",
        user_id: "u1",
        habit_id: null,
        reward_id: "reward-chocolate",
        amount: -50,
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        deleted_at: null,
      };
      const result = normalizeTrade(spendTrade);

      expect(result.reward_id).toBe("reward-chocolate");
      expect(result.habit_id).toBeNull();
      expect(result.amount).toBe(-50);
    });

    test("preserves deleted_at when set", () => {
      const deletedTrade = {
        id: "1",
        amount: 10,
        deleted_at: "2024-01-15T00:00:00Z",
      };
      const result = normalizeTrade(deletedTrade);

      expect(result.deleted_at).toBe("2024-01-15T00:00:00Z");
    });

    test("preserves zero amount", () => {
      const data = { id: "1", amount: 0 };
      const result = normalizeTrade(data);

      expect(result.amount).toBe(0);
    });

    test("preserves negative amounts (spending)", () => {
      const data = { id: "1", amount: -100 };
      const result = normalizeTrade(data);

      expect(result.amount).toBe(-100);
    });
  });
});
