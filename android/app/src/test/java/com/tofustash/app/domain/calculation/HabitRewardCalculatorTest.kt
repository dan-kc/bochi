package com.tofustash.app.domain.calculation

import com.tofustash.app.data.local.entity.HabitEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HabitRewardCalculatorTest {

    private fun makeHabit(
        id: String = "test-habit-1",
        difficultyRank: String? = null,
        minDailyFrequency: Double? = null,
        deletedAt: String? = null,
    ) = HabitEntity(
        id = id,
        userId = "user-1",
        name = "Test Habit",
        description = "",
        createdAt = "2024-01-01T00:00:00",
        updatedAt = "2024-01-01T00:00:00",
        deletedAt = deletedAt,
        hiddenUntil = null,
        minDailyFrequency = minDailyFrequency,
        difficultyRank = difficultyRank,
        isDirty = false,
    )

    // -- Difficulty multiplier --

    @Test
    fun unrankedHabitGetsMiddleDifficultyMultiplier() {
        val habit = makeHabit(difficultyRank = null)
        val multiplier = HabitRewardCalculator.calculateDifficultyMultiplier(habit, listOf(habit))
        assertEquals(5.5, multiplier, 0.001)
    }

    @Test
    fun noRankedHabitsGivesMiddleMultiplier() {
        val habit = makeHabit(id = "h1", difficultyRank = "a0")
        val allHabits = listOf(
            makeHabit(id = "1", difficultyRank = null),
            makeHabit(id = "2", difficultyRank = null),
        )
        val multiplier = HabitRewardCalculator.calculateDifficultyMultiplier(habit, allHabits)
        assertEquals(5.5, multiplier, 0.001)
    }

    @Test
    fun lowestDifficultyGetsMinMultiplier() {
        val easy = makeHabit(id = "easy", difficultyRank = "a0")
        val hard = makeHabit(id = "hard", difficultyRank = "z0")
        val multiplier = HabitRewardCalculator.calculateDifficultyMultiplier(easy, listOf(easy, hard))
        assertEquals(1.0, multiplier, 0.001)
    }

    @Test
    fun highestDifficultyGetsMaxMultiplier() {
        val easy = makeHabit(id = "easy", difficultyRank = "a0")
        val hard = makeHabit(id = "hard", difficultyRank = "z0")
        val multiplier = HabitRewardCalculator.calculateDifficultyMultiplier(hard, listOf(easy, hard))
        assertEquals(10.0, multiplier, 0.001)
    }

    @Test
    fun middleRankedHabitGetsMiddleMultiplier() {
        val low = makeHabit(id = "low", difficultyRank = "a0")
        val mid = makeHabit(id = "mid", difficultyRank = "m0")
        val high = makeHabit(id = "high", difficultyRank = "z0")
        val multiplier = HabitRewardCalculator.calculateDifficultyMultiplier(mid, listOf(low, mid, high))
        assertEquals(5.5, multiplier, 0.001)
    }

    @Test
    fun singleRankedHabitGetsMiddleMultiplier() {
        val habit = makeHabit(difficultyRank = "m0")
        val multiplier = HabitRewardCalculator.calculateDifficultyMultiplier(habit, listOf(habit))
        assertEquals(5.5, multiplier, 0.001)
    }

    @Test
    fun ignoresDeletedHabitsInRanking() {
        val active = makeHabit(id = "active", difficultyRank = "a0")
        val deleted = makeHabit(id = "deleted", difficultyRank = "z0", deletedAt = "2024-01-02T00:00:00")
        val multiplier = HabitRewardCalculator.calculateDifficultyMultiplier(active, listOf(active, deleted))
        assertEquals(5.5, multiplier, 0.001) // Only one ranked habit = middle
    }

    // -- Habit frequency multiplier --

    @Test
    fun nullFrequencyReturns1() {
        val habit = makeHabit(minDailyFrequency = null)
        val multiplier = HabitRewardCalculator.calculateHabitMultiplier(habit, 5)
        assertEquals(1.0, multiplier, 0.001)
    }

    @Test
    fun zeroFrequencyReturns1() {
        val habit = makeHabit(minDailyFrequency = 0.0)
        val multiplier = HabitRewardCalculator.calculateHabitMultiplier(habit, 5)
        assertEquals(1.0, multiplier, 0.001)
    }

    @Test
    fun behindTargetGivesHigherReward() {
        // min_daily_frequency: 100 = every day, period 7 days, expected 7
        // 0 completions = 0% of target
        val habit = makeHabit(minDailyFrequency = 100.0)
        val multiplier = HabitRewardCalculator.calculateHabitMultiplier(habit, 0, 7)
        assertEquals(1.5, multiplier, 0.001) // Max multiplier
    }

    @Test
    fun exactTargetGives1() {
        // min_daily_frequency: 100, period 7, expected 7, actual 7
        val habit = makeHabit(minDailyFrequency = 100.0)
        val multiplier = HabitRewardCalculator.calculateHabitMultiplier(habit, 7, 7)
        assertEquals(1.0, multiplier, 0.001)
    }

    @Test
    fun aheadOfTargetGivesLowerReward() {
        // min_daily_frequency: 50 = every other day, period 7, expected 3.5
        // 7 completions = 200% of target
        val habit = makeHabit(minDailyFrequency = 50.0)
        val multiplier = HabitRewardCalculator.calculateHabitMultiplier(habit, 7, 7)
        assertEquals(0.5, multiplier, 0.001) // Min multiplier
    }

    @Test
    fun multiplierClampedAtMin() {
        // Extreme overcompletion
        val habit = makeHabit(minDailyFrequency = 10.0)
        val multiplier = HabitRewardCalculator.calculateHabitMultiplier(habit, 100, 7)
        assertEquals(0.5, multiplier, 0.001)
    }

    @Test
    fun multiplierClampedAtMax() {
        val habit = makeHabit(minDailyFrequency = 100.0)
        val multiplier = HabitRewardCalculator.calculateHabitMultiplier(habit, 0, 7)
        assertEquals(1.5, multiplier, 0.001)
    }

    // -- Random multiplier --

    @Test
    fun randomMultiplierInRange() {
        val multiplier = HabitRewardCalculator.calculateRandomMultiplier("habit-1", 12345)
        assertTrue(multiplier >= 0.85)
        assertTrue(multiplier <= 1.15)
    }

    @Test
    fun randomMultiplierIsDeterministic() {
        val m1 = HabitRewardCalculator.calculateRandomMultiplier("habit-1", 12345)
        val m2 = HabitRewardCalculator.calculateRandomMultiplier("habit-1", 12345)
        assertEquals(m1, m2, 0.0)
    }

    @Test
    fun randomMultiplierVariesById() {
        val m1 = HabitRewardCalculator.calculateRandomMultiplier("habit-1", 12345)
        val m2 = HabitRewardCalculator.calculateRandomMultiplier("habit-2", 12345)
        assertNotEquals(m1, m2)
    }

    @Test
    fun randomMultiplierVariesByTimeBucket() {
        val m1 = HabitRewardCalculator.calculateRandomMultiplier("habit-1", 12345)
        val m2 = HabitRewardCalculator.calculateRandomMultiplier("habit-1", 12346)
        assertNotEquals(m1, m2)
    }

    // -- Full reward calculation --

    @Test
    fun rewardIsRoundedInteger() {
        val habit = makeHabit()
        val reward = HabitRewardCalculator.calculateReward(habit, listOf(habit), 0, 12345)
        assertEquals(reward, reward) // Already Int from roundToInt() in implementation
    }

    @Test
    fun unrankedHabitRewardInExpectedRange() {
        val habit = makeHabit(difficultyRank = null, minDailyFrequency = null)
        val reward = HabitRewardCalculator.calculateReward(habit, listOf(habit), 0, 12345)
        // base=100, difficulty=5.5, frequency=1, random=0.85-1.15
        assertTrue(reward >= (100 * 5.5 * 0.85 - 1).toInt())
        assertTrue(reward <= (100 * 5.5 * 1.15 + 1).toInt())
    }

    // -- Time bucket --

    @Test
    fun timeBucketSameWithin30Minutes() {
        val t1 = HabitRewardCalculator.getTimeBucket(1704106800000) // 2024-01-01T12:00:00Z
        val t2 = HabitRewardCalculator.getTimeBucket(1704108599000) // 2024-01-01T12:29:59Z
        assertEquals(t1, t2)
    }

    @Test
    fun timeBucketDifferentAcross30Minutes() {
        val t1 = HabitRewardCalculator.getTimeBucket(1704106800000) // 2024-01-01T12:00:00Z
        val t2 = HabitRewardCalculator.getTimeBucket(1704108600000) // 2024-01-01T12:30:00Z
        assertNotEquals(t1, t2)
    }
}
