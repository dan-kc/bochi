package com.tofustash.app.domain.calculation

import com.tofustash.app.data.local.entity.RewardEntity
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Calculates dynamic tofu costs for purchasing rewards.
 *
 * Formula: price = BASE_PRICE * damage * frequency * random
 *
 * Key difference from habits:
 * - Habits: LESS usage = HIGHER reward (incentivize doing more)
 * - Rewards: LESS usage = LOWER price (discount for restraint)
 */
object RewardPriceCalculator {

    const val BASE_PRICE = 1000

    private const val MIN_DAMAGE_MULTIPLIER = 1.0
    private const val MAX_DAMAGE_MULTIPLIER = 10.0

    private const val MIN_FREQUENCY_MULTIPLIER = 0.5
    private const val MAX_FREQUENCY_MULTIPLIER = 1.5

    private const val MIN_RANDOM_MULTIPLIER = 0.85
    private const val MAX_RANDOM_MULTIPLIER = 1.15

    private const val DEFAULT_PERIOD_DAYS = 60

    fun calculateDamageMultiplier(reward: RewardEntity, allRewards: List<RewardEntity>): Double {
        val rankedRewards = allRewards
            .filter { it.damageRank != null && it.deletedAt == null }
            .sortedBy { it.damageRank }

        if (rankedRewards.isEmpty() || reward.damageRank == null) {
            return (MIN_DAMAGE_MULTIPLIER + MAX_DAMAGE_MULTIPLIER) / 2
        }

        val position = rankedRewards.indexOfFirst { it.id == reward.id }
        if (position == -1) {
            return (MIN_DAMAGE_MULTIPLIER + MAX_DAMAGE_MULTIPLIER) / 2
        }

        val normalizedPosition = if (rankedRewards.size == 1) 0.5
        else position.toDouble() / (rankedRewards.size - 1)

        return MIN_DAMAGE_MULTIPLIER +
            normalizedPosition * (MAX_DAMAGE_MULTIPLIER - MIN_DAMAGE_MULTIPLIER)
    }

    fun calculateFrequencyMultiplier(
        reward: RewardEntity,
        purchasesInPeriod: Int,
        periodDays: Int = DEFAULT_PERIOD_DAYS,
    ): Double {
        val freq = reward.maxDailyFrequency
        if (freq == null || freq == 0.0) return 1.0

        val expectedPurchases = (freq / 100.0) * periodDays
        if (expectedPurchases == 0.0) return 1.0

        val ratio = purchasesInPeriod.toDouble() / expectedPurchases

        return if (ratio <= 1) {
            // Less than expected: discount
            MIN_FREQUENCY_MULTIPLIER + ratio * (1.0 - MIN_FREQUENCY_MULTIPLIER)
        } else {
            // More than expected: premium
            val premium = (ratio - 1) * 0.5
            min(MAX_FREQUENCY_MULTIPLIER, 1.0 + premium)
        }
    }

    fun calculateRandomMultiplier(itemId: String, timeBucket: Long): Double {
        val seed = "$itemId-$timeBucket"
        val hash = deterministicHash(seed)
        return MIN_RANDOM_MULTIPLIER + hash * (MAX_RANDOM_MULTIPLIER - MIN_RANDOM_MULTIPLIER)
    }

    fun calculatePrice(
        reward: RewardEntity,
        allRewards: List<RewardEntity>,
        purchasesInPeriod: Int = 0,
        timeBucket: Long = getTimeBucket(),
    ): Int {
        val damage = calculateDamageMultiplier(reward, allRewards)
        val frequency = calculateFrequencyMultiplier(reward, purchasesInPeriod)
        val random = calculateRandomMultiplier(reward.id, timeBucket)
        return (BASE_PRICE * damage * frequency * random).roundToInt()
    }

    data class PriceBreakdown(
        val base: Int,
        val damageMultiplier: Double,
        val frequencyMultiplier: Double,
        val randomMultiplier: Double,
    )

    data class PriceWithBreakdown(
        val price: Int,
        val breakdown: PriceBreakdown,
    )

    fun calculatePriceWithBreakdown(
        reward: RewardEntity,
        allRewards: List<RewardEntity>,
        purchasesInPeriod: Int = 0,
        timeBucket: Long = getTimeBucket(),
    ): PriceWithBreakdown {
        val damage = calculateDamageMultiplier(reward, allRewards)
        val frequency = calculateFrequencyMultiplier(reward, purchasesInPeriod)
        val random = calculateRandomMultiplier(reward.id, timeBucket)
        val price = (BASE_PRICE * damage * frequency * random).roundToInt()
        return PriceWithBreakdown(
            price = price,
            breakdown = PriceBreakdown(BASE_PRICE, damage, frequency, random),
        )
    }
}
