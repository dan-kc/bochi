import { describe, test, expect } from "vitest";
import {
  calculateDamageMultiplier,
  calculateFrequencyMultiplier,
  calculateRandomMultiplier,
  calculatePrice,
  calculatePriceWithBreakdown,
  getCurrentTimeBucket,
  BASE_PRICE,
} from "./rewardPriceCalculation";
import type { Reward } from "./reward";

// Helper to create test rewards
function createReward(overrides: Partial<Reward> = {}): Reward {
  return {
    id: "test-reward-1",
    user_id: "user-1",
    name: "Test Reward",
    description: "",
    created_at: "2024-01-01T00:00:00Z",
    updated_at: "2024-01-01T00:00:00Z",
    deleted_at: null,
    max_daily_frequency: null,
    damage_rank: null,
    ...overrides,
  };
}

describe("rewardPriceCalculation", () => {
  describe("BASE_PRICE", () => {
    test("base price is 1000 tofu", () => {
      expect(BASE_PRICE).toBe(1000);
    });
  });

  describe("calculateDamageMultiplier", () => {
    test("returns middle multiplier when reward has no damage rank", () => {
      const reward = createReward({ damage_rank: null });
      const allRewards = [reward];
      const multiplier = calculateDamageMultiplier(reward, allRewards);
      // Middle = (1 + 10) / 2 = 5.5
      expect(multiplier).toBe(5.5);
    });

    test("returns middle multiplier when no rewards have damage ranks", () => {
      const reward = createReward({ damage_rank: "a0" });
      const allRewards = [
        createReward({ id: "1", damage_rank: null }),
        createReward({ id: "2", damage_rank: null }),
      ];
      const multiplier = calculateDamageMultiplier(reward, allRewards);
      expect(multiplier).toBe(5.5);
    });

    test("lowest damage rank gets minimum multiplier", () => {
      const lowDamage = createReward({ id: "low", damage_rank: "a0" });
      const highDamage = createReward({ id: "high", damage_rank: "z0" });
      const allRewards = [lowDamage, highDamage];

      const multiplier = calculateDamageMultiplier(lowDamage, allRewards);
      expect(multiplier).toBe(1); // MIN_DAMAGE_MULTIPLIER
    });

    test("highest damage rank gets maximum multiplier", () => {
      const lowDamage = createReward({ id: "low", damage_rank: "a0" });
      const highDamage = createReward({ id: "high", damage_rank: "z0" });
      const allRewards = [lowDamage, highDamage];

      const multiplier = calculateDamageMultiplier(highDamage, allRewards);
      expect(multiplier).toBe(10); // MAX_DAMAGE_MULTIPLIER
    });

    test("middle ranked reward gets middle multiplier", () => {
      const low = createReward({ id: "low", damage_rank: "a0" });
      const mid = createReward({ id: "mid", damage_rank: "m0" });
      const high = createReward({ id: "high", damage_rank: "z0" });
      const allRewards = [low, mid, high];

      const multiplier = calculateDamageMultiplier(mid, allRewards);
      // Position 1 of 3 (0-indexed), normalized = 0.5, multiplier = 1 + 0.5 * 9 = 5.5
      expect(multiplier).toBe(5.5);
    });

    test("single ranked reward gets middle multiplier", () => {
      const reward = createReward({ damage_rank: "m0" });
      const allRewards = [reward];

      const multiplier = calculateDamageMultiplier(reward, allRewards);
      expect(multiplier).toBe(5.5);
    });

    test("ignores deleted rewards in ranking", () => {
      const active = createReward({ id: "active", damage_rank: "a0" });
      const deleted = createReward({
        id: "deleted",
        damage_rank: "z0",
        deleted_at: "2024-01-02T00:00:00Z",
      });
      const allRewards = [active, deleted];

      // With deleted ignored, active is the only ranked reward
      const multiplier = calculateDamageMultiplier(active, allRewards);
      expect(multiplier).toBe(5.5); // Single reward = middle
    });
  });

  describe("calculateFrequencyMultiplier", () => {
    test("returns 1 when max_daily_frequency is null", () => {
      const reward = createReward({ max_daily_frequency: null });
      const multiplier = calculateFrequencyMultiplier(reward, 5);
      expect(multiplier).toBe(1);
    });

    test("returns 1 when max_daily_frequency is 0", () => {
      const reward = createReward({ max_daily_frequency: 0 });
      const multiplier = calculateFrequencyMultiplier(reward, 5);
      expect(multiplier).toBe(1);
    });

    test("less purchases than expected = cheaper (multiplier < 1)", () => {
      // max_daily_frequency: 50 means every other day expected
      // Over 60 days, expected = 0.5 * 60 = 30 purchases
      // If only 15 purchases (50% of expected), should be cheap
      const reward = createReward({ max_daily_frequency: 50 });
      const multiplier = calculateFrequencyMultiplier(reward, 15, 60);
      // ratio = 15/30 = 0.5, less usage = cheaper
      // multiplier = 0.5 + (1 - 0.5) * 0.5 = 0.75
      expect(multiplier).toBe(0.75);
    });

    test("exact target = multiplier of 1", () => {
      // max_daily_frequency: 100 means every day
      // Over 60 days, expected = 60 purchases
      const reward = createReward({ max_daily_frequency: 100 });
      const multiplier = calculateFrequencyMultiplier(reward, 60, 60);
      expect(multiplier).toBe(1);
    });

    test("more purchases than expected = expensive (multiplier > 1)", () => {
      // max_daily_frequency: 50 means every other day expected
      // Over 60 days, expected = 30 purchases
      // If 60 purchases (200% of expected), should be expensive
      const reward = createReward({ max_daily_frequency: 50 });
      const multiplier = calculateFrequencyMultiplier(reward, 60, 60);
      // ratio = 60/30 = 2.0, more usage = more expensive
      // multiplier = 1 + min(0.5, (2.0 - 1) * 0.5) = 1.5
      expect(multiplier).toBe(1.5);
    });

    test("multiplier is capped at 0.5 minimum", () => {
      // Even with zero purchases, can't go below 0.5
      const reward = createReward({ max_daily_frequency: 100 });
      const multiplier = calculateFrequencyMultiplier(reward, 0, 60);
      expect(multiplier).toBe(0.5);
    });

    test("multiplier is capped at 1.5 maximum", () => {
      // Even with extreme overuse, can't go above 1.5
      const reward = createReward({ max_daily_frequency: 10 });
      // Expected = 0.1 * 60 = 6 purchases, actual = 100
      const multiplier = calculateFrequencyMultiplier(reward, 100, 60);
      expect(multiplier).toBe(1.5);
    });
  });

  describe("calculateRandomMultiplier", () => {
    test("returns value between 0.85 and 1.15", () => {
      const multiplier = calculateRandomMultiplier("reward-1", 12345);
      expect(multiplier).toBeGreaterThanOrEqual(0.85);
      expect(multiplier).toBeLessThanOrEqual(1.15);
    });

    test("is deterministic for same inputs", () => {
      const m1 = calculateRandomMultiplier("reward-1", 12345);
      const m2 = calculateRandomMultiplier("reward-1", 12345);
      expect(m1).toBe(m2);
    });

    test("varies by reward ID", () => {
      const m1 = calculateRandomMultiplier("reward-1", 12345);
      const m2 = calculateRandomMultiplier("reward-2", 12345);
      expect(m1).not.toBe(m2);
    });

    test("varies by time bucket", () => {
      const m1 = calculateRandomMultiplier("reward-1", 12345);
      const m2 = calculateRandomMultiplier("reward-1", 12346);
      expect(m1).not.toBe(m2);
    });
  });

  describe("calculatePrice", () => {
    test("returns rounded integer", () => {
      const reward = createReward();
      const price = calculatePrice(reward, [reward], 0);
      expect(Number.isInteger(price)).toBe(true);
    });

    test("unranked reward with no frequency gets base price * middle damage * random", () => {
      const reward = createReward({ damage_rank: null, max_daily_frequency: null });
      const price = calculatePrice(reward, [reward], 0, 12345);
      // base=1000, damage=5.5, frequency=1, random varies
      // Price should be around 5500 ± 15%
      expect(price).toBeGreaterThan(1000 * 5.5 * 0.85 - 1);
      expect(price).toBeLessThan(1000 * 5.5 * 1.15 + 1);
    });

    test("low damage, low usage = cheap", () => {
      const lowDamage = createReward({
        id: "low",
        damage_rank: "a0",
        max_daily_frequency: 50,
      });
      const highDamage = createReward({
        id: "high",
        damage_rank: "z0",
        max_daily_frequency: 50,
      });
      const allRewards = [lowDamage, highDamage];

      // 0 purchases in 60 days = very low usage
      const price = calculatePrice(lowDamage, allRewards, 0, 12345);
      // damage=1, frequency=0.5 (min), random varies
      // Should be around 500 ± 15%
      expect(price).toBeLessThan(1000 * 1 * 0.5 * 1.15 + 50);
    });

    test("high damage, high usage = expensive", () => {
      const lowDamage = createReward({
        id: "low",
        damage_rank: "a0",
        max_daily_frequency: 10,
      });
      const highDamage = createReward({
        id: "high",
        damage_rank: "z0",
        max_daily_frequency: 10,
      });
      const allRewards = [lowDamage, highDamage];

      // 100 purchases when expected is only 6 = extreme overuse
      const price = calculatePrice(highDamage, allRewards, 100, 12345);
      // damage=10, frequency=1.5 (max), random varies
      // Should be around 15000 ± 15%
      expect(price).toBeGreaterThan(1000 * 10 * 1.5 * 0.85 - 50);
    });
  });

  describe("calculatePriceWithBreakdown", () => {
    test("returns price and all multiplier breakdown", () => {
      const reward = createReward({
        damage_rank: "m0",
        max_daily_frequency: 50,
      });
      const result = calculatePriceWithBreakdown(reward, [reward], 30, 12345);

      expect(result).toHaveProperty("price");
      expect(result).toHaveProperty("breakdown");
      expect(result.breakdown).toHaveProperty("base", 1000);
      expect(result.breakdown).toHaveProperty("damageMultiplier");
      expect(result.breakdown).toHaveProperty("frequencyMultiplier");
      expect(result.breakdown).toHaveProperty("randomMultiplier");
    });

    test("breakdown multipliers multiply to give price", () => {
      const reward = createReward({
        damage_rank: "m0",
        max_daily_frequency: 50,
      });
      const result = calculatePriceWithBreakdown(reward, [reward], 30, 12345);

      const calculated =
        result.breakdown.base *
        result.breakdown.damageMultiplier *
        result.breakdown.frequencyMultiplier *
        result.breakdown.randomMultiplier;

      expect(result.price).toBe(Math.round(calculated));
    });
  });

  describe("getCurrentTimeBucket", () => {
    test("returns a number", () => {
      const bucket = getCurrentTimeBucket();
      expect(typeof bucket).toBe("number");
    });

    test("same for dates within same 30-minute window", () => {
      const date1 = new Date("2024-01-01T12:00:00Z");
      const date2 = new Date("2024-01-01T12:29:59Z");
      expect(getCurrentTimeBucket(date1)).toBe(getCurrentTimeBucket(date2));
    });

    test("different for dates in different 30-minute windows", () => {
      const date1 = new Date("2024-01-01T12:00:00Z");
      const date2 = new Date("2024-01-01T12:30:00Z");
      expect(getCurrentTimeBucket(date1)).not.toBe(getCurrentTimeBucket(date2));
    });
  });
});
