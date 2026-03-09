import { describe, test, expect } from "vitest";
import {
  calculateDamageMultiplier,
  calculateFrequencyMultiplier,
  calculateRandomMultiplier,
  calculatePrice,
  calculatePriceWithBreakdown,
  getCurrentTimeBucket,
} from "./rewardPriceCalculation";
import type { Reward } from "./reward";

// Helper to create test rewards
function createReward(overrides: Partial<Reward> = {}): Reward {
  return {
    id: "test-reward-1",
    user_id: "user-1",
    name: "Test Reward",
    description: "",
    created_at: "2020-01-01T00:00:00Z", // old enough for full age blending
    updated_at: "2020-01-01T00:00:00Z",
    deleted_at: null,
    max_daily_frequency: null,
    damage_rank: null,
    ...overrides,
  };
}

describe("rewardPriceCalculation", () => {
  describe("calculateDamageMultiplier", () => {
    test("returns 0.5 when reward has no damage rank", () => {
      const reward = createReward({ damage_rank: null });
      const allRewards = [reward];
      const multiplier = calculateDamageMultiplier(reward, allRewards);
      expect(multiplier).toBe(0.5);
    });

    test("returns 0.5 when no rewards have damage ranks", () => {
      const reward = createReward({ damage_rank: "a0" });
      const allRewards = [
        createReward({ id: "1", damage_rank: null }),
        createReward({ id: "2", damage_rank: null }),
      ];
      const multiplier = calculateDamageMultiplier(reward, allRewards);
      expect(multiplier).toBe(0.5);
    });

    test("single ranked reward gets D = 1/2", () => {
      const reward = createReward({ damage_rank: "m0" });
      const allRewards = [reward];

      const multiplier = calculateDamageMultiplier(reward, allRewards);
      // N=1, rank=1: (1 - 1 + 1) / (1 + 1) = 1/2
      expect(multiplier).toBe(0.5);
    });

    test("lowest rank gets highest D value in two-item list", () => {
      const lowDamage = createReward({ id: "low", damage_rank: "a0" });
      const highDamage = createReward({ id: "high", damage_rank: "z0" });
      const allRewards = [lowDamage, highDamage];

      // N=2, rank=1 (lowest): (2 - 1 + 1) / (2 + 1) = 2/3
      const multiplier = calculateDamageMultiplier(lowDamage, allRewards);
      expect(multiplier).toBeCloseTo(2 / 3);
    });

    test("highest rank gets lowest D value in two-item list", () => {
      const lowDamage = createReward({ id: "low", damage_rank: "a0" });
      const highDamage = createReward({ id: "high", damage_rank: "z0" });
      const allRewards = [lowDamage, highDamage];

      // N=2, rank=2 (highest): (2 - 2 + 1) / (2 + 1) = 1/3
      const multiplier = calculateDamageMultiplier(highDamage, allRewards);
      expect(multiplier).toBeCloseTo(1 / 3);
    });

    test("middle ranked reward in three-item list", () => {
      const low = createReward({ id: "low", damage_rank: "a0" });
      const mid = createReward({ id: "mid", damage_rank: "m0" });
      const high = createReward({ id: "high", damage_rank: "z0" });
      const allRewards = [low, mid, high];

      // N=3, rank=2: (3 - 2 + 1) / (3 + 1) = 2/4 = 0.5
      const multiplier = calculateDamageMultiplier(mid, allRewards);
      expect(multiplier).toBe(0.5);
    });

    test("ignores deleted rewards in ranking", () => {
      const active = createReward({ id: "active", damage_rank: "a0" });
      const deleted = createReward({
        id: "deleted",
        damage_rank: "z0",
        deleted_at: "2024-01-02T00:00:00Z",
      });
      const allRewards = [active, deleted];

      // With deleted ignored, active is the only ranked reward -> 1/2
      const multiplier = calculateDamageMultiplier(active, allRewards);
      expect(multiplier).toBe(0.5);
    });

    test("D is always in (0, 1)", () => {
      const rewards = Array.from({ length: 10 }, (_, i) =>
        createReward({ id: `r${i}`, damage_rank: `${String.fromCharCode(97 + i)}0` })
      );

      for (const reward of rewards) {
        const d = calculateDamageMultiplier(reward, rewards);
        expect(d).toBeGreaterThan(0);
        expect(d).toBeLessThan(1);
      }
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

    test("zero purchases for mature reward gives F_r near 1", () => {
      const reward = createReward({ max_daily_frequency: 50 });
      const multiplier = calculateFrequencyMultiplier(reward, 0, 60);
      // r=0, w=1 (old reward), r_eff=0, F_r = 2/(1-0) - 1 = 1
      expect(multiplier).toBe(1);
    });

    test("moderate usage increases multiplier", () => {
      const reward = createReward({ max_daily_frequency: 100 });
      // Expected = 60, actual = 30, r = 0.5
      const multiplier = calculateFrequencyMultiplier(reward, 30, 60);
      // r_eff = 0.5, F_r = 2/(1 - 0.5^3) - 1 = 2/(1-0.125) - 1 = 2/0.875 - 1 ≈ 1.286
      expect(multiplier).toBeGreaterThan(1);
      expect(multiplier).toBeLessThan(2);
    });

    test("high usage spikes multiplier asymptotically", () => {
      const reward = createReward({ max_daily_frequency: 100 });
      // Expected = 60, actual = 54, r = 0.9
      const multiplier = calculateFrequencyMultiplier(reward, 54, 60);
      // r_eff = 0.9, F_r = 2/(1 - 0.9^3) - 1 = 2/(1-0.729) - 1 = 2/0.271 - 1 ≈ 6.38
      expect(multiplier).toBeGreaterThan(5);
      expect(multiplier).toBeLessThan(10);
    });

    test("clamps to max when r_eff >= 1", () => {
      const reward = createReward({ max_daily_frequency: 100 });
      // Expected = 60, actual = 60, r = 1.0, r_eff = 1.0
      const multiplier = calculateFrequencyMultiplier(reward, 60, 60);
      expect(multiplier).toBe(50);
    });

    test("clamps to max when over limit", () => {
      const reward = createReward({ max_daily_frequency: 50 });
      // Expected = 30, actual = 60, r = 2.0
      const multiplier = calculateFrequencyMultiplier(reward, 60, 60);
      expect(multiplier).toBe(50);
    });

    test("caps at 50 for very high but sub-1 r_eff", () => {
      const reward = createReward({ max_daily_frequency: 100 });
      // r_eff = 0.99, F_r = 2/(1 - 0.99^3) - 1 ≈ 66 -> capped at 50
      const multiplier = calculateFrequencyMultiplier(reward, 59.4, 60);
      expect(multiplier).toBeLessThanOrEqual(50);
    });

    test("new reward uses age blending (defaults toward 0.5)", () => {
      // Brand new reward (created today)
      const now = new Date().toISOString();
      const reward = createReward({ max_daily_frequency: 100, created_at: now });
      // r=0, w≈0, r_eff ≈ 0.5
      const multiplier = calculateFrequencyMultiplier(reward, 0, 60);
      // F_r = 2/(1 - 0.5^3) - 1 = 2/0.875 - 1 ≈ 1.286
      expect(multiplier).toBeCloseTo(2 / 0.875 - 1, 1);
    });
  });

  describe("calculateRandomMultiplier", () => {
    test("returns value between 0.9 and 1.1", () => {
      const multiplier = calculateRandomMultiplier("reward-1", 12345);
      expect(multiplier).toBeGreaterThanOrEqual(0.9);
      expect(multiplier).toBeLessThan(1.1);
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
      const price = calculatePrice(reward, [reward], 0, 12345, 5);
      expect(Number.isInteger(price)).toBe(true);
    });

    test("unranked reward with no frequency: price = 100 * G * 0.5 * 1 * R", () => {
      const reward = createReward({ damage_rank: null, max_daily_frequency: null });
      const price = calculatePrice(reward, [reward], 0, 12345, 5);
      // 100 * 5 * 0.5 * 1 * R, R in [0.9, 1.1)
      expect(price).toBeGreaterThanOrEqual(Math.round(100 * 5 * 0.5 * 0.9));
      expect(price).toBeLessThan(Math.round(100 * 5 * 0.5 * 1.1) + 1);
    });

    test("returns capped price when r_eff >= 1", () => {
      const reward = createReward({ max_daily_frequency: 100 });
      // r_eff >= 1 -> frequency capped at 50
      const price = calculatePrice(reward, [reward], 60, 12345, 5);
      expect(isFinite(price)).toBe(true);
      expect(price).toBeGreaterThan(0);
    });

    test("generalDifficulty scales price linearly", () => {
      const reward = createReward({ damage_rank: null, max_daily_frequency: null });
      const price1 = calculatePrice(reward, [reward], 0, 12345, 1);
      const price10 = calculatePrice(reward, [reward], 0, 12345, 10);
      // price10 should be ~10x price1
      expect(price10).toBeCloseTo(price1 * 10, -1);
    });
  });

  describe("calculatePriceWithBreakdown", () => {
    test("returns price and all multiplier breakdown", () => {
      const reward = createReward({
        damage_rank: "m0",
        max_daily_frequency: 50,
      });
      const result = calculatePriceWithBreakdown(reward, [reward], 0, 12345, 5);

      expect(result).toHaveProperty("price");
      expect(result).toHaveProperty("breakdown");
      expect(result.breakdown).toHaveProperty("generalDifficulty", 5);
      expect(result.breakdown).toHaveProperty("damageMultiplier");
      expect(result.breakdown).toHaveProperty("frequencyMultiplier");
      expect(result.breakdown).toHaveProperty("randomMultiplier");
    });

    test("breakdown multipliers multiply to give price", () => {
      const reward = createReward({
        damage_rank: "m0",
        max_daily_frequency: 50,
      });
      const result = calculatePriceWithBreakdown(reward, [reward], 0, 12345, 5);

      const calculated =
        100 *
        result.breakdown.generalDifficulty *
        result.breakdown.damageMultiplier *
        result.breakdown.frequencyMultiplier *
        result.breakdown.randomMultiplier;

      expect(result.price).toBe(Math.round(calculated));
    });

    test("returns capped price when r_eff >= 1", () => {
      const reward = createReward({ max_daily_frequency: 100 });
      const result = calculatePriceWithBreakdown(reward, [reward], 60, 12345, 5);
      expect(isFinite(result.price)).toBe(true);
      expect(result.breakdown.frequencyMultiplier).toBe(50);
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
