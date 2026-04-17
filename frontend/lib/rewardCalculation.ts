/**
 * Reward Calculation Formula
 *
 * Calculates dynamic tofu rewards for completing habits.
 *
 * Formula: Reward = 100 * G * D * F * R
 *   G = general difficulty (user-configurable scalar, default 5.0)
 *   D = (N - rank + 1) / (N + 1), relative difficulty in (0, 1)
 *   F = 2 / (1 + r_eff^α), α=2.5, frequency multiplier in (0, 2)
 *     r_eff = w * r + (1 - w) * 1.0, w = min(1, age_days / 30)
 *   R = 0.993 + 0.014 * rand(), deterministic random in [0.993, 1.007)
 */

import type { Habit } from './habit';

/** Frequency exponent for habit reward formula */
const ALPHA = 2.5;

/** Age blending period in days */
const AGE_BLEND_DAYS = 30;

/** Default frequency neutral point for new habits */
const HABIT_NEUTRAL_RATIO = 1.0;

/** Keep dynamic pricing subtle instead of letting randomness dominate rewards */
const RANDOM_BASE_MULTIPLIER = 0.993;
const RANDOM_MULTIPLIER_RANGE = 0.014;

/** Time bucket size in milliseconds (30 minutes) */
const TIME_BUCKET_MS = 30 * 60 * 1000;

/**
 * Deterministic hash function for strings with good avalanche properties.
 * Returns a value between 0 and 1.
 * Uses MurmurHash3-inspired mixing for better distribution.
 */
function deterministicHash(input: string): number {
  let h1 = 0xdeadbeef;
  let h2 = 0x41c6ce57;

  for (let i = 0; i < input.length; i++) {
    const char = input.charCodeAt(i);
    h1 = Math.imul(h1 ^ char, 2654435761);
    h2 = Math.imul(h2 ^ char, 1597334677);
  }

  // Final mixing for avalanche effect
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507);
  h1 = Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  h1 ^= h1 >>> 16;

  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507);
  h2 = Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 ^= h2 >>> 16;

  // Combine both hashes and convert to 0-1 range
  const combined = (h1 ^ h2) >>> 0;
  return combined / 0xffffffff;
}

/**
 * Get the current time bucket (30-minute interval since epoch).
 */
export function getCurrentTimeBucket(now: Date = new Date()): number {
  return Math.floor(now.getTime() / TIME_BUCKET_MS);
}

/**
 * Calculate difficulty multiplier based on habit position in difficulty ranking.
 * D = (N - rank + 1) / (N + 1), where rank is 1-indexed position.
 * Range: (0, 1), never reaches 0 or 1.
 */
export function calculateDifficultyMultiplier(
  habit: Habit,
  allHabits: Habit[]
): number {
  const rankedHabits = allHabits
    .filter((h) => h.difficulty_rank !== null && h.deleted_at === null)
    .sort((a, b) => (a.difficulty_rank! < b.difficulty_rank! ? -1 : 1));

  if (rankedHabits.length === 0 || habit.difficulty_rank === null) {
    return 0.5;
  }

  const position = rankedHabits.findIndex((h) => h.id === habit.id);
  if (position === -1) {
    return 0.5;
  }

  const N = rankedHabits.length;
  const rank = position + 1; // 1-indexed
  return (N - rank + 1) / (N + 1);
}

/**
 * Calculate habit frequency multiplier with age blending.
 * F = 2 / (1 + r_eff^α), α=2.5
 * r_eff = w * r + (1 - w) * 1.0, where w = min(1, age_days / 30)
 * Range: (0, 2)
 */
export function calculateHabitMultiplier(
  habit: Habit,
  completionsInPeriod: number,
  periodDays: number = 7
): number {
  if (habit.min_daily_frequency === null || habit.min_daily_frequency === 0) {
    return 1;
  }

  const expectedCompletions = (habit.min_daily_frequency / 100) * periodDays;

  if (expectedCompletions === 0) {
    return 1;
  }

  const r = completionsInPeriod / expectedCompletions;

  // Age blending
  const ageDays = getAgeDays(habit.created_at);
  const w = Math.min(1, ageDays / AGE_BLEND_DAYS);
  const rEff = w * r + (1 - w) * HABIT_NEUTRAL_RATIO;

  return 2 / (1 + Math.pow(rEff, ALPHA));
}

/**
 * Calculate deterministic "random" multiplier.
 * Range: [0.993, 1.007)
 */
export function calculateRandomMultiplier(
  habitId: string,
  timeBucket: number
): number {
  const seed = `${habitId}-${timeBucket}`;
  const hash = deterministicHash(seed);
  return RANDOM_BASE_MULTIPLIER + hash * RANDOM_MULTIPLIER_RANGE;
}

/**
 * Calculate the full reward amount for completing a habit.
 *
 * Formula: Reward = 100 * G * D * F * R
 */
export function calculateReward(
  habit: Habit,
  allHabits: Habit[],
  completionsInPeriod: number = 0,
  timeBucket: number = getCurrentTimeBucket(),
  generalDifficulty: number = 5.0,
): number {
  const difficultyMultiplier = calculateDifficultyMultiplier(habit, allHabits);
  const habitMultiplier = calculateHabitMultiplier(habit, completionsInPeriod);
  const randomMultiplier = calculateRandomMultiplier(habit.id, timeBucket);

  const reward =
    100 *
    generalDifficulty *
    difficultyMultiplier *
    habitMultiplier *
    randomMultiplier;

  return Math.round(reward);
}

/**
 * Calculate reward with breakdown of each factor (useful for debugging/display).
 */
export function calculateRewardWithBreakdown(
  habit: Habit,
  allHabits: Habit[],
  completionsInPeriod: number = 0,
  timeBucket: number = getCurrentTimeBucket(),
  generalDifficulty: number = 5.0,
): {
  reward: number;
  breakdown: {
    generalDifficulty: number;
    difficultyMultiplier: number;
    habitMultiplier: number;
    randomMultiplier: number;
  };
} {
  const difficultyMultiplier = calculateDifficultyMultiplier(habit, allHabits);
  const habitMultiplier = calculateHabitMultiplier(habit, completionsInPeriod);
  const randomMultiplier = calculateRandomMultiplier(habit.id, timeBucket);

  const reward =
    100 *
    generalDifficulty *
    difficultyMultiplier *
    habitMultiplier *
    randomMultiplier;

  return {
    reward: Math.round(reward),
    breakdown: {
      generalDifficulty,
      difficultyMultiplier,
      habitMultiplier,
      randomMultiplier,
    },
  };
}

/**
 * Get age in days from a created_at timestamp string.
 */
function getAgeDays(createdAt: string): number {
  const created = new Date(createdAt);
  const now = new Date();
  return (now.getTime() - created.getTime()) / (1000 * 60 * 60 * 24);
}
