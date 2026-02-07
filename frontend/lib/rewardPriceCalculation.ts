/**
 * Reward Price Calculation Formula
 *
 * Calculates dynamic tofu costs for purchasing rewards based on:
 * 1. Damage (main factor) - higher damage = more expensive
 * 2. Usage frequency - not meeting max frequency = cheaper (discount up to 50%)
 * 3. Deterministic "random" element - varies by ±15% based on reward ID + time bucket
 *
 * The formula is deterministic: given the same inputs and time bucket,
 * all frontends will calculate the same price.
 *
 * Key difference from habits:
 * - Habits: LESS usage = HIGHER reward (incentivize doing more)
 * - Rewards: LESS usage = LOWER price (discount for restraint)
 */

import type { Reward } from "./reward";

/** Base price amount in tofu */
export const BASE_PRICE = 1000;

/** Damage multiplier range: lowest damage = 1x, highest = 10x */
const MIN_DAMAGE_MULTIPLIER = 1;
const MAX_DAMAGE_MULTIPLIER = 10;

/** Frequency multiplier range: ±50% from base */
const MIN_FREQUENCY_MULTIPLIER = 0.5;
const MAX_FREQUENCY_MULTIPLIER = 1.5;

/** Random element range: ±15% from base */
const MIN_RANDOM_MULTIPLIER = 0.85;
const MAX_RANDOM_MULTIPLIER = 1.15;

/** Time bucket size in milliseconds (30 minutes) */
const TIME_BUCKET_MS = 30 * 60 * 1000;

/** Default period for frequency calculation (60 days = ~2 months) */
const DEFAULT_PERIOD_DAYS = 60;

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
 * Calculate damage multiplier based on reward position in damage ranking.
 * Higher damage = higher multiplier = more expensive.
 *
 * @param reward - The reward to calculate for
 * @param allRewards - All rewards for the user (to determine relative damage)
 * @returns Multiplier between MIN_DAMAGE_MULTIPLIER and MAX_DAMAGE_MULTIPLIER
 */
export function calculateDamageMultiplier(
  reward: Reward,
  allRewards: Reward[]
): number {
  // Filter to rewards with damage ranks and sort by rank
  const rankedRewards = allRewards
    .filter((r) => r.damage_rank !== null && r.deleted_at === null)
    .sort((a, b) => (a.damage_rank! < b.damage_rank! ? -1 : 1));

  if (rankedRewards.length === 0 || reward.damage_rank === null) {
    // Unranked reward gets middle damage
    return (MIN_DAMAGE_MULTIPLIER + MAX_DAMAGE_MULTIPLIER) / 2;
  }

  // Find position in sorted list (0 = lowest damage, length-1 = highest damage)
  const position = rankedRewards.findIndex((r) => r.id === reward.id);
  if (position === -1) {
    return (MIN_DAMAGE_MULTIPLIER + MAX_DAMAGE_MULTIPLIER) / 2;
  }

  // Convert position to 0-1 scale
  const normalizedPosition =
    rankedRewards.length === 1 ? 0.5 : position / (rankedRewards.length - 1);

  // Map to multiplier range
  return (
    MIN_DAMAGE_MULTIPLIER +
    normalizedPosition * (MAX_DAMAGE_MULTIPLIER - MIN_DAMAGE_MULTIPLIER)
  );
}

/**
 * Calculate frequency multiplier based on usage vs max_daily_frequency.
 * LESS usage = CHEAPER (discount for restraint).
 * MORE usage = MORE EXPENSIVE (premium for overuse).
 *
 * @param reward - The reward to calculate for
 * @param purchasesInPeriod - Number of purchases in the measurement period
 * @param periodDays - The measurement period in days (default: 60)
 * @returns Multiplier between MIN_FREQUENCY_MULTIPLIER and MAX_FREQUENCY_MULTIPLIER
 */
export function calculateFrequencyMultiplier(
  reward: Reward,
  purchasesInPeriod: number,
  periodDays: number = DEFAULT_PERIOD_DAYS
): number {
  if (reward.max_daily_frequency === null || reward.max_daily_frequency === 0) {
    return 1;
  }

  // Expected purchases = max_daily_frequency * periodDays
  // Note: max_daily_frequency is 0-100, representing percentage of days
  // So max_daily_frequency=100 means every day, 50 means every other day
  const expectedPurchases = (reward.max_daily_frequency / 100) * periodDays;

  if (expectedPurchases === 0) {
    return 1;
  }

  // Calculate usage ratio
  // ratio < 1 = using less than expected, ratio > 1 = using more than expected
  const ratio = purchasesInPeriod / expectedPurchases;

  // For rewards:
  // - ratio = 0 (0% of expected) -> multiplier = 0.5 (50% discount)
  // - ratio = 1 (100% of expected) -> multiplier = 1.0 (base price)
  // - ratio = 2+ (200%+ of expected) -> multiplier = 1.5 (50% premium)

  if (ratio <= 1) {
    // Less than expected: discount
    // Linear interpolation from 0.5 (at ratio 0) to 1.0 (at ratio 1)
    return MIN_FREQUENCY_MULTIPLIER + ratio * (1 - MIN_FREQUENCY_MULTIPLIER);
  } else {
    // More than expected: premium
    // Linear increase from 1.0 (at ratio 1) to 1.5 (at ratio 2+)
    const premium = (ratio - 1) * 0.5;
    return Math.min(MAX_FREQUENCY_MULTIPLIER, 1 + premium);
  }
}

/**
 * Calculate deterministic "random" multiplier.
 * This provides price variation while ensuring all frontends show the same value.
 *
 * @param rewardId - The reward ID
 * @param timeBucket - The 30-minute time bucket (use getCurrentTimeBucket())
 * @returns Multiplier between MIN_RANDOM_MULTIPLIER and MAX_RANDOM_MULTIPLIER
 */
export function calculateRandomMultiplier(
  rewardId: string,
  timeBucket: number
): number {
  // Combine reward ID and time bucket for deterministic variation
  const seed = `${rewardId}-${timeBucket}`;
  const hash = deterministicHash(seed);

  // Map hash (0-1) to multiplier range
  return MIN_RANDOM_MULTIPLIER + hash * (MAX_RANDOM_MULTIPLIER - MIN_RANDOM_MULTIPLIER);
}

/**
 * Calculate the full price for purchasing a reward.
 *
 * Formula:
 *   price = BASE_PRICE * damage * frequency * random
 *
 * @param reward - The reward to calculate price for
 * @param allRewards - All rewards for the user (for damage ranking)
 * @param purchasesInPeriod - Reward purchases in last 60 days
 * @param timeBucket - The time bucket for random element (use getCurrentTimeBucket())
 * @returns The price in tofu (rounded to integer)
 */
export function calculatePrice(
  reward: Reward,
  allRewards: Reward[],
  purchasesInPeriod: number = 0,
  timeBucket: number = getCurrentTimeBucket()
): number {
  const damageMultiplier = calculateDamageMultiplier(reward, allRewards);
  const frequencyMultiplier = calculateFrequencyMultiplier(reward, purchasesInPeriod);
  const randomMultiplier = calculateRandomMultiplier(reward.id, timeBucket);

  const price =
    BASE_PRICE *
    damageMultiplier *
    frequencyMultiplier *
    randomMultiplier;

  return Math.round(price);
}

/**
 * Calculate price with breakdown of each factor (useful for debugging/display).
 */
export function calculatePriceWithBreakdown(
  reward: Reward,
  allRewards: Reward[],
  purchasesInPeriod: number = 0,
  timeBucket: number = getCurrentTimeBucket()
): {
  price: number;
  breakdown: {
    base: number;
    damageMultiplier: number;
    frequencyMultiplier: number;
    randomMultiplier: number;
  };
} {
  const damageMultiplier = calculateDamageMultiplier(reward, allRewards);
  const frequencyMultiplier = calculateFrequencyMultiplier(reward, purchasesInPeriod);
  const randomMultiplier = calculateRandomMultiplier(reward.id, timeBucket);

  const price =
    BASE_PRICE *
    damageMultiplier *
    frequencyMultiplier *
    randomMultiplier;

  return {
    price: Math.round(price),
    breakdown: {
      base: BASE_PRICE,
      damageMultiplier,
      frequencyMultiplier,
      randomMultiplier,
    },
  };
}
