/**
 * Reward Calculation Formula
 *
 * Calculates dynamic tofu rewards for completing habits based on:
 * 1. Difficulty (main factor) - higher difficulty = larger reward
 * 2. Habit frequency - not meeting target frequency = larger reward (capped at ±50%)
 * 3. Deterministic "random" element - varies by ±15% based on habit ID + time bucket
 *
 * The formula is deterministic: given the same inputs and time bucket,
 * all frontends will calculate the same reward amount.
 */

import type { Habit } from './habit';

/** Base reward amount in tofu */
const BASE_REWARD = 100;

/** Difficulty multiplier range: easiest habit = 1x, hardest = 10x */
const MIN_DIFFICULTY_MULTIPLIER = 1;
const MAX_DIFFICULTY_MULTIPLIER = 10;

/** Habit frequency multiplier range: ±50% from base */
const MIN_HABIT_MULTIPLIER = 0.5;
const MAX_HABIT_MULTIPLIER = 1.5;

/** Random element range: ±15% from base */
const MIN_RANDOM_MULTIPLIER = 0.85;
const MAX_RANDOM_MULTIPLIER = 1.15;

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
 *
 * @param habit - The habit to calculate for
 * @param allHabits - All habits for the user (to determine relative difficulty)
 * @returns Multiplier between MIN_DIFFICULTY_MULTIPLIER and MAX_DIFFICULTY_MULTIPLIER
 */
export function calculateDifficultyMultiplier(
  habit: Habit,
  allHabits: Habit[]
): number {
  // Filter to habits with difficulty ranks and sort by rank
  const rankedHabits = allHabits
    .filter((h) => h.difficulty_rank !== null && h.deleted_at === null)
    .sort((a, b) => (a.difficulty_rank! < b.difficulty_rank! ? -1 : 1));

  if (rankedHabits.length === 0 || habit.difficulty_rank === null) {
    // Unranked habit gets middle difficulty
    return (MIN_DIFFICULTY_MULTIPLIER + MAX_DIFFICULTY_MULTIPLIER) / 2;
  }

  // Find position in sorted list (0 = easiest, length-1 = hardest)
  const position = rankedHabits.findIndex((h) => h.id === habit.id);
  if (position === -1) {
    return (MIN_DIFFICULTY_MULTIPLIER + MAX_DIFFICULTY_MULTIPLIER) / 2;
  }

  // Convert position to 0-1 scale
  const normalizedPosition =
    rankedHabits.length === 1 ? 0.5 : position / (rankedHabits.length - 1);

  // Map to multiplier range
  return (
    MIN_DIFFICULTY_MULTIPLIER +
    normalizedPosition * (MAX_DIFFICULTY_MULTIPLIER - MIN_DIFFICULTY_MULTIPLIER)
  );
}

/**
 * Calculate habit frequency multiplier.
 * Habits that are behind their target frequency get higher rewards.
 *
 * @param habit - The habit to calculate for
 * @param completionsInPeriod - Number of completions in the measurement period
 * @param periodDays - The measurement period in days (default: 7)
 * @returns Multiplier between MIN_HABIT_MULTIPLIER and MAX_HABIT_MULTIPLIER
 */
export function calculateHabitMultiplier(
  habit: Habit,
  completionsInPeriod: number,
  periodDays: number = 7
): number {
  if (habit.min_daily_frequency === null || habit.min_daily_frequency === 0) {
    return 1;
  }

  // Expected completions = min_daily_frequency * periodDays
  // Note: min_daily_frequency is 0-100, representing percentage of days
  // So min_daily_frequency=100 means every day, 50 means every other day
  const expectedCompletions = (habit.min_daily_frequency / 100) * periodDays;

  if (expectedCompletions === 0) {
    return 1;
  }

  // Calculate how well the target is being met
  // ratio < 1 = behind target, ratio > 1 = ahead of target
  const ratio = completionsInPeriod / expectedCompletions;

  // Invert and clamp: behind target = higher reward, ahead = lower reward
  // ratio 0.5 (50% of target) -> multiplier 1.5
  // ratio 1.0 (100% of target) -> multiplier 1.0
  // ratio 1.5 (150% of target) -> multiplier 0.75
  // ratio 2.0+ (200%+ of target) -> multiplier 0.5

  // Map ratio to multiplier: multiplier = 1.5 - (ratio * 0.5), clamped
  const rawMultiplier = MAX_HABIT_MULTIPLIER - ratio * 0.5;

  return Math.max(MIN_HABIT_MULTIPLIER, Math.min(MAX_HABIT_MULTIPLIER, rawMultiplier));
}

/**
 * Calculate deterministic "random" multiplier.
 * This provides price variation while ensuring all frontends show the same value.
 *
 * @param habitId - The habit ID
 * @param timeBucket - The 30-minute time bucket (use getCurrentTimeBucket())
 * @returns Multiplier between MIN_RANDOM_MULTIPLIER and MAX_RANDOM_MULTIPLIER
 */
export function calculateRandomMultiplier(
  habitId: string,
  timeBucket: number
): number {
  // Combine habit ID and time bucket for deterministic variation
  const seed = `${habitId}-${timeBucket}`;
  const hash = deterministicHash(seed);
  const multiplier = MIN_RANDOM_MULTIPLIER + hash * (MAX_RANDOM_MULTIPLIER - MIN_RANDOM_MULTIPLIER);

  // Map hash (0-1) to multiplier range
  return multiplier;
}

/**
 * Calculate the full reward amount for completing a habit.
 *
 * Formula:
 *   reward = BASE_REWARD * difficulty * habit * random
 *
 * @param habit - The habit to calculate reward for
 * @param allHabits - All habits for the user (for difficulty ranking)
 * @param completionsInPeriod - Habit completions in last 7 days
 * @param timeBucket - The time bucket for random element (use getCurrentTimeBucket())
 * @returns The reward amount in tofu (rounded to integer)
 */
export function calculateReward(
  habit: Habit,
  allHabits: Habit[],
  completionsInPeriod: number = 0,
  timeBucket: number = getCurrentTimeBucket(),
): number {
  const difficultyMultiplier = calculateDifficultyMultiplier(habit, allHabits);
  const habitMultiplier = calculateHabitMultiplier(habit, completionsInPeriod);
  const randomMultiplier = calculateRandomMultiplier(habit.id, timeBucket);

  const reward =
    BASE_REWARD *
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
): {
  reward: number;
  breakdown: {
    base: number;
    difficultyMultiplier: number;
    habitMultiplier: number;
    randomMultiplier: number;
  };
} {
  const difficultyMultiplier = calculateDifficultyMultiplier(habit, allHabits);
  const habitMultiplier = calculateHabitMultiplier(habit, completionsInPeriod);
  const randomMultiplier = calculateRandomMultiplier(habit.id, timeBucket);

  const reward =
    BASE_REWARD *
    difficultyMultiplier *
    habitMultiplier *
    randomMultiplier;

  return {
    reward: Math.round(reward),
    breakdown: {
      base: BASE_REWARD,
      difficultyMultiplier,
      habitMultiplier,
      randomMultiplier,
    },
  };
}
