/**
 * Reward Price Calculation Formula
 *
 * Calculates dynamic tofu costs for purchasing rewards.
 *
 * Formula: Cost = 100 * G * D_r * F_r * R
 *   G = general difficulty (user-configurable scalar, default 5.0)
 *   D_r = (N_r - rank + 1) / (N_r + 1), relative difficulty in (0, 1)
 *   F_r = 2 / (1 - r_eff^β) - 1, β=3, asymptotic frequency in [1, ∞), capped at 50
 *     r_eff = w * r + (1 - w) * 0.5, w = min(1, age_days / 30)
 *     Hard block when r_eff >= 1
 *   R = 0.993 + 0.014 * rand(), deterministic random in [0.993, 1.007)
 */

import type { Reward } from "./reward";

/** Frequency exponent for reward cost formula */
const BETA = 3;

/** Age blending period in days */
const AGE_BLEND_DAYS = 30;

/** Default neutral ratio for new rewards */
const REWARD_NEUTRAL_RATIO = 0.5;

/** Keep dynamic pricing subtle instead of letting randomness dominate costs */
const RANDOM_BASE_MULTIPLIER = 0.993;
const RANDOM_MULTIPLIER_RANGE = 0.014;

/** Maximum frequency multiplier cap */
const MAX_FREQUENCY_MULTIPLIER = 50;

/** Default period for frequency calculation (60 days = ~2 months) */
const DEFAULT_PERIOD_DAYS = 60;

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
 * Calculate damage multiplier based on reward position in damage ranking.
 * D_r = (N_r - rank + 1) / (N_r + 1), where rank is 1-indexed.
 * Range: (0, 1), never reaches 0 or 1.
 */
export function calculateDamageMultiplier(
  reward: Reward,
  allRewards: Reward[]
): number {
  const rankedRewards = allRewards
    .filter((r) => r.damage_rank !== null && r.deleted_at === null)
    .sort((a, b) => (a.damage_rank! < b.damage_rank! ? -1 : 1));

  if (rankedRewards.length === 0 || reward.damage_rank === null) {
    return 0.5;
  }

  const position = rankedRewards.findIndex((r) => r.id === reward.id);
  if (position === -1) {
    return 0.5;
  }

  const N = rankedRewards.length;
  const rank = position + 1; // 1-indexed
  return (N - rank + 1) / (N + 1);
}

/**
 * Calculate asymptotic frequency multiplier for reward costs.
 * F_r = 2 / (1 - r_eff^β) - 1, β=3
 * r_eff = w * r + (1 - w) * 0.5, where w = min(1, age_days / 30)
 * Range: [1, 50], clamped to MAX_FREQUENCY_MULTIPLIER.
 */
export function calculateFrequencyMultiplier(
  reward: Reward,
  purchasesInPeriod: number,
  periodDays: number = DEFAULT_PERIOD_DAYS
): number {
  if (reward.max_daily_frequency === null || reward.max_daily_frequency === 0) {
    return 1;
  }

  const expectedPurchases = (reward.max_daily_frequency / 100) * periodDays;

  if (expectedPurchases === 0) {
    return 1;
  }

  const r = purchasesInPeriod / expectedPurchases;

  // Age blending
  const ageDays = getAgeDays(reward.created_at);
  const w = Math.min(1, ageDays / AGE_BLEND_DAYS);
  const rEff = w * r + (1 - w) * REWARD_NEUTRAL_RATIO;

  // Clamp r_eff below 1 so the formula stays finite
  if (rEff >= 1) {
    return MAX_FREQUENCY_MULTIPLIER;
  }

  const Fr = 2 / (1 - Math.pow(rEff, BETA)) - 1;
  return Math.min(Fr, MAX_FREQUENCY_MULTIPLIER);
}

/**
 * Calculate deterministic "random" multiplier.
 * Range: [0.993, 1.007)
 */
export function calculateRandomMultiplier(
  rewardId: string,
  timeBucket: number
): number {
  const seed = `${rewardId}-${timeBucket}`;
  const hash = deterministicHash(seed);
  return RANDOM_BASE_MULTIPLIER + hash * RANDOM_MULTIPLIER_RANGE;
}

/**
 * Calculate the full price for purchasing a reward.
 *
 * Formula: Cost = 100 * G * D_r * F_r * R
 */
export function calculatePrice(
  reward: Reward,
  allRewards: Reward[],
  purchasesInPeriod: number = 0,
  timeBucket: number = getCurrentTimeBucket(),
  generalDifficulty: number = 5.0,
): number {
  const damageMultiplier = calculateDamageMultiplier(reward, allRewards);
  const frequencyMultiplier = calculateFrequencyMultiplier(reward, purchasesInPeriod);
  const randomMultiplier = calculateRandomMultiplier(reward.id, timeBucket);

  const price =
    100 *
    generalDifficulty *
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
  timeBucket: number = getCurrentTimeBucket(),
  generalDifficulty: number = 5.0,
): {
  price: number;
  breakdown: {
    generalDifficulty: number;
    damageMultiplier: number;
    frequencyMultiplier: number;
    randomMultiplier: number;
  };
} {
  const damageMultiplier = calculateDamageMultiplier(reward, allRewards);
  const frequencyMultiplier = calculateFrequencyMultiplier(reward, purchasesInPeriod);
  const randomMultiplier = calculateRandomMultiplier(reward.id, timeBucket);

  const price =
    100 *
    generalDifficulty *
    damageMultiplier *
    frequencyMultiplier *
    randomMultiplier;

  return {
    price: Math.round(price),
    breakdown: {
      generalDifficulty,
      damageMultiplier,
      frequencyMultiplier,
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
