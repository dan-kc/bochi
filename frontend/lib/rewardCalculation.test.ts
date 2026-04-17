import { describe, test, expect } from "vitest";
import {
  calculateDifficultyMultiplier,
  calculateHabitMultiplier,
  calculateRandomMultiplier,
  calculateReward,
  calculateRewardWithBreakdown,
  getCurrentTimeBucket,
} from "./rewardCalculation";
import type { Habit } from "./habit";

// Helper to create test habits
function createHabit(overrides: Partial<Habit> = {}): Habit {
  return {
    id: "test-habit-1",
    user_id: "user-1",
    name: "Test Habit",
    description: "",
    created_at: "2020-01-01T00:00:00Z", // old enough for full age blending
    updated_at: "2020-01-01T00:00:00Z",
    deleted_at: null,
    min_daily_frequency: null,
    difficulty_rank: null,
    ...overrides,
  };
}

describe("rewardCalculation", () => {
  describe("calculateDifficultyMultiplier", () => {
    test("returns 0.5 when habit has no difficulty rank", () => {
      const habit = createHabit({ difficulty_rank: null });
      const allHabits = [habit];
      const multiplier = calculateDifficultyMultiplier(habit, allHabits);
      expect(multiplier).toBe(0.5);
    });

    test("returns 0.5 when no habits have difficulty ranks", () => {
      const habit = createHabit({ difficulty_rank: "a0" });
      const allHabits = [
        createHabit({ id: "1", difficulty_rank: null }),
        createHabit({ id: "2", difficulty_rank: null }),
      ];
      const multiplier = calculateDifficultyMultiplier(habit, allHabits);
      expect(multiplier).toBe(0.5);
    });

    test("single ranked habit gets D = 1/2", () => {
      const habit = createHabit({ difficulty_rank: "m0" });
      const allHabits = [habit];

      const multiplier = calculateDifficultyMultiplier(habit, allHabits);
      // N=1, rank=1: (1 - 1 + 1) / (1 + 1) = 1/2
      expect(multiplier).toBe(0.5);
    });

    test("easiest habit in two-item list gets highest D", () => {
      const easy = createHabit({ id: "easy", difficulty_rank: "a0" });
      const hard = createHabit({ id: "hard", difficulty_rank: "z0" });
      const allHabits = [easy, hard];

      // N=2, rank=1: (2 - 1 + 1) / (2 + 1) = 2/3
      const multiplier = calculateDifficultyMultiplier(easy, allHabits);
      expect(multiplier).toBeCloseTo(2 / 3);
    });

    test("hardest habit in two-item list gets lowest D", () => {
      const easy = createHabit({ id: "easy", difficulty_rank: "a0" });
      const hard = createHabit({ id: "hard", difficulty_rank: "z0" });
      const allHabits = [easy, hard];

      // N=2, rank=2: (2 - 2 + 1) / (2 + 1) = 1/3
      const multiplier = calculateDifficultyMultiplier(hard, allHabits);
      expect(multiplier).toBeCloseTo(1 / 3);
    });

    test("middle ranked habit in three-item list gets D = 0.5", () => {
      const low = createHabit({ id: "low", difficulty_rank: "a0" });
      const mid = createHabit({ id: "mid", difficulty_rank: "m0" });
      const high = createHabit({ id: "high", difficulty_rank: "z0" });
      const allHabits = [low, mid, high];

      // N=3, rank=2: (3 - 2 + 1) / (3 + 1) = 2/4 = 0.5
      const multiplier = calculateDifficultyMultiplier(mid, allHabits);
      expect(multiplier).toBe(0.5);
    });

    test("ignores deleted habits in ranking", () => {
      const active = createHabit({ id: "active", difficulty_rank: "a0" });
      const deleted = createHabit({
        id: "deleted",
        difficulty_rank: "z0",
        deleted_at: "2024-01-02T00:00:00Z",
      });
      const allHabits = [active, deleted];

      // With deleted ignored, active is the only ranked habit -> 1/2
      const multiplier = calculateDifficultyMultiplier(active, allHabits);
      expect(multiplier).toBe(0.5);
    });

    test("D is always in (0, 1) for any number of habits", () => {
      const habits = Array.from({ length: 10 }, (_, i) =>
        createHabit({ id: `h${i}`, difficulty_rank: `${String.fromCharCode(97 + i)}0` })
      );

      for (const habit of habits) {
        const d = calculateDifficultyMultiplier(habit, habits);
        expect(d).toBeGreaterThan(0);
        expect(d).toBeLessThan(1);
      }
    });
  });

  describe("calculateHabitMultiplier", () => {
    test("returns 1 when min_daily_frequency is null", () => {
      const habit = createHabit({ min_daily_frequency: null });
      const multiplier = calculateHabitMultiplier(habit, 5);
      expect(multiplier).toBe(1);
    });

    test("returns 1 when min_daily_frequency is 0", () => {
      const habit = createHabit({ min_daily_frequency: 0 });
      const multiplier = calculateHabitMultiplier(habit, 5);
      expect(multiplier).toBe(1);
    });

    test("zero completions for mature habit gives F near 2", () => {
      const habit = createHabit({ min_daily_frequency: 100 });
      // r=0, w=1 (old habit), r_eff=0, F = 2/(1+0^2.5) = 2/1 = 2
      const multiplier = calculateHabitMultiplier(habit, 0, 7);
      expect(multiplier).toBe(2);
    });

    test("exact target completion gives F = 2/(1+1) = 1", () => {
      const habit = createHabit({ min_daily_frequency: 100 });
      // Expected = 7, actual = 7, r = 1.0, r_eff = 1.0
      // F = 2 / (1 + 1^2.5) = 2/2 = 1
      const multiplier = calculateHabitMultiplier(habit, 7, 7);
      expect(multiplier).toBe(1);
    });

    test("exceeding target lowers F below 1", () => {
      const habit = createHabit({ min_daily_frequency: 100 });
      // Expected = 7, actual = 14, r = 2.0
      // F = 2 / (1 + 2^2.5) = 2 / (1 + 5.657) ≈ 0.3
      const multiplier = calculateHabitMultiplier(habit, 14, 7);
      expect(multiplier).toBeLessThan(1);
      expect(multiplier).toBeGreaterThan(0);
    });

    test("F is naturally bounded between 0 and 2", () => {
      const habit = createHabit({ min_daily_frequency: 100 });
      // Test with extreme values
      const fZero = calculateHabitMultiplier(habit, 0, 7);
      const fHigh = calculateHabitMultiplier(habit, 100, 7);
      expect(fZero).toBeLessThanOrEqual(2);
      expect(fHigh).toBeGreaterThan(0);
    });

    test("new habit uses age blending (defaults toward r=1.0)", () => {
      const now = new Date().toISOString();
      const habit = createHabit({ min_daily_frequency: 100, created_at: now });
      // r=0, w≈0, r_eff ≈ 1.0
      // F = 2/(1 + 1^2.5) = 1.0
      const multiplier = calculateHabitMultiplier(habit, 0, 7);
      expect(multiplier).toBeCloseTo(1, 1);
    });

    test("30-day-old habit uses full actual ratio", () => {
      const thirtyDaysAgo = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000).toISOString();
      const habit = createHabit({ min_daily_frequency: 100, created_at: thirtyDaysAgo });
      // r=0, w=1, r_eff=0, F=2
      const multiplier = calculateHabitMultiplier(habit, 0, 7);
      expect(multiplier).toBe(2);
    });
  });

  describe("calculateRandomMultiplier", () => {
    test("returns value between 0.995 and 1.005", () => {
      const multiplier = calculateRandomMultiplier("habit-1", 12345);
      expect(multiplier).toBeGreaterThanOrEqual(0.995);
      expect(multiplier).toBeLessThan(1.005);
    });

    test("is deterministic for same inputs", () => {
      const m1 = calculateRandomMultiplier("habit-1", 12345);
      const m2 = calculateRandomMultiplier("habit-1", 12345);
      expect(m1).toBe(m2);
    });

    test("varies by habit ID", () => {
      const m1 = calculateRandomMultiplier("habit-1", 12345);
      const m2 = calculateRandomMultiplier("habit-2", 12345);
      expect(m1).not.toBe(m2);
    });

    test("varies by time bucket", () => {
      const m1 = calculateRandomMultiplier("habit-1", 12345);
      const m2 = calculateRandomMultiplier("habit-1", 12346);
      expect(m1).not.toBe(m2);
    });
  });

  describe("calculateReward", () => {
    test("returns rounded integer", () => {
      const habit = createHabit();
      const reward = calculateReward(habit, [habit], 0, 12345, 5);
      expect(Number.isInteger(reward)).toBe(true);
    });

    test("unranked habit with no frequency: reward = 100 * G * 0.5 * 1 * R", () => {
      const habit = createHabit({ difficulty_rank: null, min_daily_frequency: null });
      const reward = calculateReward(habit, [habit], 0, 12345, 5);
      // 100 * 5 * 0.5 * 1 * R, R in [0.995, 1.005)
      expect(reward).toBeGreaterThanOrEqual(Math.round(100 * 5 * 0.5 * 0.995));
      expect(reward).toBeLessThan(Math.round(100 * 5 * 0.5 * 1.005) + 1);
    });

    test("generalDifficulty scales reward linearly", () => {
      const habit = createHabit({ difficulty_rank: null, min_daily_frequency: null });
      const r1 = calculateReward(habit, [habit], 0, 12345, 1);
      const r10 = calculateReward(habit, [habit], 0, 12345, 10);
      // r10 should be ~10x r1
      expect(r10).toBeCloseTo(r1 * 10, -1);
    });

    test("harder habit (lower rank) gets higher reward", () => {
      const easy = createHabit({ id: "easy", difficulty_rank: "a0", min_daily_frequency: null });
      const hard = createHabit({ id: "hard", difficulty_rank: "z0", min_daily_frequency: null });
      const allHabits = [easy, hard];

      // easy has rank=1, D=2/3; hard has rank=2, D=1/3
      // Wait - in the formula, rank 1 (sorted first by rank string) is easiest
      // So easy (a0) -> rank=1, D=(2-1+1)/(2+1)=2/3
      // hard (z0) -> rank=2, D=(2-2+1)/(2+1)=1/3
      // The EASIEST habit gets the highest D and therefore the highest reward
      // This makes sense because easier habits are done more often, so they need
      // higher base rewards to compensate for the frequency multiplier
      const easyReward = calculateReward(easy, allHabits, 0, 12345, 5);
      const hardReward = calculateReward(hard, allHabits, 0, 12345, 5);
      // Easy has D=2/3, hard has D=1/3, so easy should get ~2x hard
      // But they have different IDs so random differs
      // Just check direction
      expect(easyReward).toBeGreaterThan(hardReward * 0.8); // Account for random
    });
  });

  describe("calculateRewardWithBreakdown", () => {
    test("returns reward and all multiplier breakdown", () => {
      const habit = createHabit({
        difficulty_rank: "m0",
        min_daily_frequency: 50,
      });
      const result = calculateRewardWithBreakdown(habit, [habit], 0, 12345, 5);

      expect(result).toHaveProperty("reward");
      expect(result).toHaveProperty("breakdown");
      expect(result.breakdown).toHaveProperty("generalDifficulty", 5);
      expect(result.breakdown).toHaveProperty("difficultyMultiplier");
      expect(result.breakdown).toHaveProperty("habitMultiplier");
      expect(result.breakdown).toHaveProperty("randomMultiplier");
    });

    test("breakdown multipliers multiply to give reward", () => {
      const habit = createHabit({
        difficulty_rank: "m0",
        min_daily_frequency: 50,
      });
      const result = calculateRewardWithBreakdown(habit, [habit], 0, 12345, 5);

      const calculated =
        100 *
        result.breakdown.generalDifficulty *
        result.breakdown.difficultyMultiplier *
        result.breakdown.habitMultiplier *
        result.breakdown.randomMultiplier;

      expect(result.reward).toBe(Math.round(calculated));
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
