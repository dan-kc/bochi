package com.tofustash.app.domain.calculation

import com.tofustash.app.data.local.entity.RewardEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RewardPriceCalculatorTest {

    private fun makeReward(
        id: String = "test-reward-1",
        damageRank: String? = null,
        maxDailyFrequency: Double? = null,
        deletedAt: String? = null,
    ) = RewardEntity(
        id = id,
        userId = "user-1",
        name = "Test Reward",
        description = "",
        createdAt = "2024-01-01T00:00:00",
        updatedAt = "2024-01-01T00:00:00",
        deletedAt = deletedAt,
        hiddenUntil = null,
        maxDailyFrequency = maxDailyFrequency,
        damageRank = damageRank,
        isDirty = false,
    )

    @Test
    fun basePriceIs1000() {
        assertEquals(1000, RewardPriceCalculator.BASE_PRICE)
    }

    // -- Damage multiplier --

    @Test
    fun unrankedRewardGetsMiddleDamageMultiplier() {
        val reward = makeReward(damageRank = null)
        val multiplier = RewardPriceCalculator.calculateDamageMultiplier(reward, listOf(reward))
        assertEquals(5.5, multiplier, 0.001)
    }

    @Test
    fun noRankedRewardsGivesMiddleMultiplier() {
        val reward = makeReward(id = "r1", damageRank = "a0")
        val allRewards = listOf(
            makeReward(id = "1", damageRank = null),
            makeReward(id = "2", damageRank = null),
        )
        val multiplier = RewardPriceCalculator.calculateDamageMultiplier(reward, allRewards)
        assertEquals(5.5, multiplier, 0.001)
    }

    @Test
    fun lowestDamageGetsMinMultiplier() {
        val low = makeReward(id = "low", damageRank = "a0")
        val high = makeReward(id = "high", damageRank = "z0")
        val multiplier = RewardPriceCalculator.calculateDamageMultiplier(low, listOf(low, high))
        assertEquals(1.0, multiplier, 0.001)
    }

    @Test
    fun highestDamageGetsMaxMultiplier() {
        val low = makeReward(id = "low", damageRank = "a0")
        val high = makeReward(id = "high", damageRank = "z0")
        val multiplier = RewardPriceCalculator.calculateDamageMultiplier(high, listOf(low, high))
        assertEquals(10.0, multiplier, 0.001)
    }

    @Test
    fun middleRankedRewardGetsMiddleMultiplier() {
        val low = makeReward(id = "low", damageRank = "a0")
        val mid = makeReward(id = "mid", damageRank = "m0")
        val high = makeReward(id = "high", damageRank = "z0")
        val multiplier = RewardPriceCalculator.calculateDamageMultiplier(mid, listOf(low, mid, high))
        assertEquals(5.5, multiplier, 0.001)
    }

    @Test
    fun singleRankedRewardGetsMiddleMultiplier() {
        val reward = makeReward(damageRank = "m0")
        val multiplier = RewardPriceCalculator.calculateDamageMultiplier(reward, listOf(reward))
        assertEquals(5.5, multiplier, 0.001)
    }

    @Test
    fun ignoresDeletedRewardsInRanking() {
        val active = makeReward(id = "active", damageRank = "a0")
        val deleted = makeReward(id = "deleted", damageRank = "z0", deletedAt = "2024-01-02T00:00:00")
        val multiplier = RewardPriceCalculator.calculateDamageMultiplier(active, listOf(active, deleted))
        assertEquals(5.5, multiplier, 0.001)
    }

    // -- Frequency multiplier --

    @Test
    fun nullFrequencyReturns1() {
        val reward = makeReward(maxDailyFrequency = null)
        val multiplier = RewardPriceCalculator.calculateFrequencyMultiplier(reward, 5)
        assertEquals(1.0, multiplier, 0.001)
    }

    @Test
    fun zeroFrequencyReturns1() {
        val reward = makeReward(maxDailyFrequency = 0.0)
        val multiplier = RewardPriceCalculator.calculateFrequencyMultiplier(reward, 5)
        assertEquals(1.0, multiplier, 0.001)
    }

    @Test
    fun lessPurchasesThanExpectedIsCheaper() {
        // max_daily_frequency: 50 = every other day, period 60, expected 30
        // 15 purchases = 50% of expected
        val reward = makeReward(maxDailyFrequency = 50.0)
        val multiplier = RewardPriceCalculator.calculateFrequencyMultiplier(reward, 15, 60)
        // ratio = 0.5, multiplier = 0.5 + 0.5 * 0.5 = 0.75
        assertEquals(0.75, multiplier, 0.001)
    }

    @Test
    fun exactTargetGives1() {
        val reward = makeReward(maxDailyFrequency = 100.0)
        val multiplier = RewardPriceCalculator.calculateFrequencyMultiplier(reward, 60, 60)
        assertEquals(1.0, multiplier, 0.001)
    }

    @Test
    fun morePurchasesThanExpectedIsExpensive() {
        // max_daily_frequency: 50, period 60, expected 30
        // 60 purchases = 200% of expected
        val reward = makeReward(maxDailyFrequency = 50.0)
        val multiplier = RewardPriceCalculator.calculateFrequencyMultiplier(reward, 60, 60)
        assertEquals(1.5, multiplier, 0.001)
    }

    @Test
    fun frequencyMultiplierClampedAtMin() {
        val reward = makeReward(maxDailyFrequency = 100.0)
        val multiplier = RewardPriceCalculator.calculateFrequencyMultiplier(reward, 0, 60)
        assertEquals(0.5, multiplier, 0.001)
    }

    @Test
    fun frequencyMultiplierClampedAtMax() {
        val reward = makeReward(maxDailyFrequency = 10.0)
        val multiplier = RewardPriceCalculator.calculateFrequencyMultiplier(reward, 100, 60)
        assertEquals(1.5, multiplier, 0.001)
    }

    // -- Random multiplier --

    @Test
    fun randomMultiplierInRange() {
        val multiplier = RewardPriceCalculator.calculateRandomMultiplier("reward-1", 12345)
        assertTrue(multiplier >= 0.85)
        assertTrue(multiplier <= 1.15)
    }

    @Test
    fun randomMultiplierIsDeterministic() {
        val m1 = RewardPriceCalculator.calculateRandomMultiplier("reward-1", 12345)
        val m2 = RewardPriceCalculator.calculateRandomMultiplier("reward-1", 12345)
        assertEquals(m1, m2, 0.0)
    }

    @Test
    fun randomMultiplierVariesById() {
        val m1 = RewardPriceCalculator.calculateRandomMultiplier("reward-1", 12345)
        val m2 = RewardPriceCalculator.calculateRandomMultiplier("reward-2", 12345)
        assertNotEquals(m1, m2)
    }

    @Test
    fun randomMultiplierVariesByTimeBucket() {
        val m1 = RewardPriceCalculator.calculateRandomMultiplier("reward-1", 12345)
        val m2 = RewardPriceCalculator.calculateRandomMultiplier("reward-1", 12346)
        assertNotEquals(m1, m2)
    }

    // -- Full price calculation --

    @Test
    fun priceIsRoundedInteger() {
        val reward = makeReward()
        val price = RewardPriceCalculator.calculatePrice(reward, listOf(reward), 0, 12345)
        assertEquals(price, price) // Already Int from roundToInt() in implementation
    }

    @Test
    fun unrankedRewardPriceInExpectedRange() {
        val reward = makeReward(damageRank = null, maxDailyFrequency = null)
        val price = RewardPriceCalculator.calculatePrice(reward, listOf(reward), 0, 12345)
        // base=1000, damage=5.5, frequency=1, random=0.85-1.15
        assertTrue(price >= (1000 * 5.5 * 0.85 - 1).toInt())
        assertTrue(price <= (1000 * 5.5 * 1.15 + 1).toInt())
    }

    @Test
    fun lowDamageLowUsageIsCheap() {
        val low = makeReward(id = "low", damageRank = "a0", maxDailyFrequency = 50.0)
        val high = makeReward(id = "high", damageRank = "z0", maxDailyFrequency = 50.0)
        val price = RewardPriceCalculator.calculatePrice(low, listOf(low, high), 0, 12345)
        // damage=1, frequency=0.5, random varies
        assertTrue(price < (1000 * 1 * 0.5 * 1.15 + 50).toInt())
    }

    @Test
    fun highDamageHighUsageIsExpensive() {
        val low = makeReward(id = "low", damageRank = "a0", maxDailyFrequency = 10.0)
        val high = makeReward(id = "high", damageRank = "z0", maxDailyFrequency = 10.0)
        val price = RewardPriceCalculator.calculatePrice(high, listOf(low, high), 100, 12345)
        // damage=10, frequency=1.5, random varies
        assertTrue(price > (1000 * 10 * 1.5 * 0.85 - 50).toInt())
    }

    // -- Breakdown --

    @Test
    fun breakdownMultipliersMultiplyToPrice() {
        val reward = makeReward(damageRank = "m0", maxDailyFrequency = 50.0)
        val result = RewardPriceCalculator.calculatePriceWithBreakdown(reward, listOf(reward), 30, 12345)
        val calculated = result.breakdown.base *
            result.breakdown.damageMultiplier *
            result.breakdown.frequencyMultiplier *
            result.breakdown.randomMultiplier
        assertEquals(result.price, kotlin.math.round(calculated).toInt())
    }
}
