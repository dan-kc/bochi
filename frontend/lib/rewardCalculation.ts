/**
 * Reward Calculation Formula
 *
 * Calculates dynamic soy rewards for completing tasks based on:
 * 1. Difficulty (main factor) - higher difficulty = larger reward
 * 2. Due date proximity - closer to deadline = larger reward
 * 3. Habit frequency - not meeting target frequency = larger reward (capped at ±50%)
 * 4. Deterministic "random" element - varies by ±50% based on task ID + time bucket
 *
 * The formula is deterministic: given the same inputs and time bucket,
 * all frontends will calculate the same reward amount.
 */

import { Task } from './task';

/** Base reward amount in soy */
const BASE_REWARD = 100;

/** Difficulty multiplier range: easiest task = 1x, hardest = 10x */
const MIN_DIFFICULTY_MULTIPLIER = 1;
const MAX_DIFFICULTY_MULTIPLIER = 10;

/** Due date proximity multiplier range: far away = 1x, due today = 2x */
const MIN_DUE_DATE_MULTIPLIER = 1;
const MAX_DUE_DATE_MULTIPLIER = 2;

/** Days threshold - tasks due further than this get minimum multiplier */
const DUE_DATE_MAX_DAYS = 14;

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
 * Calculate difficulty multiplier based on task position in difficulty ranking.
 *
 * @param task - The task to calculate for
 * @param allTasks - All tasks for the user (to determine relative difficulty)
 * @returns Multiplier between MIN_DIFFICULTY_MULTIPLIER and MAX_DIFFICULTY_MULTIPLIER
 */
export function calculateDifficultyMultiplier(
  task: Task,
  allTasks: Task[]
): number {
  // Filter to tasks with difficulty ranks and sort by rank
  const rankedTasks = allTasks
    .filter((t) => t.difficulty_rank !== null && t.deleted_at === null)
    .sort((a, b) => (a.difficulty_rank! < b.difficulty_rank! ? -1 : 1));

  if (rankedTasks.length === 0 || task.difficulty_rank === null) {
    // Unranked task gets middle difficulty
    return (MIN_DIFFICULTY_MULTIPLIER + MAX_DIFFICULTY_MULTIPLIER) / 2;
  }

  // Find position in sorted list (0 = easiest, length-1 = hardest)
  const position = rankedTasks.findIndex((t) => t.id === task.id);
  if (position === -1) {
    return (MIN_DIFFICULTY_MULTIPLIER + MAX_DIFFICULTY_MULTIPLIER) / 2;
  }

  // Convert position to 0-1 scale
  const normalizedPosition =
    rankedTasks.length === 1 ? 0.5 : position / (rankedTasks.length - 1);

  // Map to multiplier range
  return (
    MIN_DIFFICULTY_MULTIPLIER +
    normalizedPosition * (MAX_DIFFICULTY_MULTIPLIER - MIN_DIFFICULTY_MULTIPLIER)
  );
}

/**
 * Calculate due date proximity multiplier.
 * Tasks due sooner get higher rewards to incentivize completion.
 *
 * @param task - The task to calculate for
 * @param now - Current time (for testing)
 * @returns Multiplier between MIN_DUE_DATE_MULTIPLIER and MAX_DUE_DATE_MULTIPLIER,
 *          or 1 if no due date
 */
export function calculateDueDateMultiplier(
  task: Task,
  now: Date = new Date()
): number {
  if (task.due_by === null) {
    return 1;
  }

  const dueDate = new Date(task.due_by);
  const daysUntilDue = (dueDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24);

  if (daysUntilDue <= 0) {
    // Overdue - maximum urgency
    return MAX_DUE_DATE_MULTIPLIER;
  }

  if (daysUntilDue >= DUE_DATE_MAX_DAYS) {
    // Far away - minimum urgency
    return MIN_DUE_DATE_MULTIPLIER;
  }

  // Linear interpolation: closer to due = higher multiplier
  const urgency = 1 - daysUntilDue / DUE_DATE_MAX_DAYS;
  return (
    MIN_DUE_DATE_MULTIPLIER +
    urgency * (MAX_DUE_DATE_MULTIPLIER - MIN_DUE_DATE_MULTIPLIER)
  );
}

/**
 * Calculate habit frequency multiplier.
 * Habits that are behind their target frequency get higher rewards.
 *
 * @param task - The task to calculate for
 * @param completionsInPeriod - Number of completions in the measurement period
 * @param periodDays - The measurement period in days (default: 7)
 * @returns Multiplier between MIN_HABIT_MULTIPLIER and MAX_HABIT_MULTIPLIER,
 *          or 1 if not a habit
 */
export function calculateHabitMultiplier(
  task: Task,
  completionsInPeriod: number,
  periodDays: number = 7
): number {
  if (task.min_daily_frequency === null || task.min_daily_frequency === 0) {
    return 1;
  }

  // Expected completions = min_daily_frequency * periodDays
  // Note: min_daily_frequency is 0-100, representing percentage of days
  // So min_daily_frequency=100 means every day, 50 means every other day
  const expectedCompletions = (task.min_daily_frequency / 100) * periodDays;

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
 * @param taskId - The task ID
 * @param timeBucket - The 30-minute time bucket (use getCurrentTimeBucket())
 * @returns Multiplier between MIN_RANDOM_MULTIPLIER and MAX_RANDOM_MULTIPLIER
 */
export function calculateRandomMultiplier(
  taskId: string,
  timeBucket: number
): number {
  // Combine task ID and time bucket for deterministic variation
  const seed = `${taskId}-${timeBucket}`;
  const hash = deterministicHash(seed);
  const multiplier = MIN_RANDOM_MULTIPLIER + hash * (MAX_RANDOM_MULTIPLIER - MIN_RANDOM_MULTIPLIER);

  // Map hash (0-1) to multiplier range
  return multiplier;
}

/**
 * Calculate the full reward amount for completing a task.
 *
 * Formula:
 *   reward = BASE_REWARD * difficulty * dueDate * habit * random
 *
 * @param task - The task to calculate reward for
 * @param allTasks - All tasks for the user (for difficulty ranking)
 * @param completionsInPeriod - Habit completions in last 7 days (0 for non-habits)
 * @param timeBucket - The time bucket for random element (use getCurrentTimeBucket())
 * @param now - Current time (for due date calculation)
 * @returns The reward amount in soy (rounded to integer)
 */
export function calculateReward(
  task: Task,
  allTasks: Task[],
  completionsInPeriod: number = 0,
  timeBucket: number = getCurrentTimeBucket(),
  now: Date = new Date()
): number {
  const difficultyMultiplier = calculateDifficultyMultiplier(task, allTasks);
  const dueDateMultiplier = calculateDueDateMultiplier(task, now);
  const habitMultiplier = calculateHabitMultiplier(task, completionsInPeriod);
  const randomMultiplier = calculateRandomMultiplier(task.id, timeBucket);

  const reward =
    BASE_REWARD *
    difficultyMultiplier *
    dueDateMultiplier *
    habitMultiplier *
    randomMultiplier;

  return Math.round(reward);
}

/**
 * Calculate reward with breakdown of each factor (useful for debugging/display).
 */
export function calculateRewardWithBreakdown(
  task: Task,
  allTasks: Task[],
  completionsInPeriod: number = 0,
  timeBucket: number = getCurrentTimeBucket(),
  now: Date = new Date()
): {
  reward: number;
  breakdown: {
    base: number;
    difficultyMultiplier: number;
    dueDateMultiplier: number;
    habitMultiplier: number;
    randomMultiplier: number;
  };
} {
  const difficultyMultiplier = calculateDifficultyMultiplier(task, allTasks);
  const dueDateMultiplier = calculateDueDateMultiplier(task, now);
  const habitMultiplier = calculateHabitMultiplier(task, completionsInPeriod);
  const randomMultiplier = calculateRandomMultiplier(task.id, timeBucket);

  const reward =
    BASE_REWARD *
    difficultyMultiplier *
    dueDateMultiplier *
    habitMultiplier *
    randomMultiplier;

  return {
    reward: Math.round(reward),
    breakdown: {
      base: BASE_REWARD,
      difficultyMultiplier,
      dueDateMultiplier,
      habitMultiplier,
      randomMultiplier,
    },
  };
}
