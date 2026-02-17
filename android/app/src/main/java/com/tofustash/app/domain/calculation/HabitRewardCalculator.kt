package com.tofustash.app.domain.calculation

import com.tofustash.app.data.local.entity.HabitEntity
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Calculates dynamic tofu rewards for completing habits.
 *
 * Formula: reward = BASE_REWARD * difficulty * habitFrequency * random
 *
 * - Difficulty: position-based ranking (1x-10x)
 * - Habit frequency: behind target = higher reward (0.5x-1.5x)
 * - Random: deterministic ±15% variation based on habitId + time bucket
 */
object HabitRewardCalculator {

    const val BASE_REWARD = 100

    private const val MIN_DIFFICULTY_MULTIPLIER = 1.0
    private const val MAX_DIFFICULTY_MULTIPLIER = 10.0

    private const val MIN_HABIT_MULTIPLIER = 0.5
    private const val MAX_HABIT_MULTIPLIER = 1.5

    private const val MIN_RANDOM_MULTIPLIER = 0.85
    private const val MAX_RANDOM_MULTIPLIER = 1.15

    fun getTimeBucket(timestampMs: Long = System.currentTimeMillis()): Long =
        com.tofustash.app.domain.calculation.getTimeBucket(timestampMs)

    fun calculateDifficultyMultiplier(habit: HabitEntity, allHabits: List<HabitEntity>): Double {
        val rankedHabits = allHabits
            .filter { it.difficultyRank != null && it.deletedAt == null }
            .sortedBy { it.difficultyRank }

        if (rankedHabits.isEmpty() || habit.difficultyRank == null) {
            return (MIN_DIFFICULTY_MULTIPLIER + MAX_DIFFICULTY_MULTIPLIER) / 2
        }

        val position = rankedHabits.indexOfFirst { it.id == habit.id }
        if (position == -1) {
            return (MIN_DIFFICULTY_MULTIPLIER + MAX_DIFFICULTY_MULTIPLIER) / 2
        }

        val normalizedPosition = if (rankedHabits.size == 1) 0.5
        else position.toDouble() / (rankedHabits.size - 1)

        return MIN_DIFFICULTY_MULTIPLIER +
            normalizedPosition * (MAX_DIFFICULTY_MULTIPLIER - MIN_DIFFICULTY_MULTIPLIER)
    }

    fun calculateHabitMultiplier(
        habit: HabitEntity,
        completionsInPeriod: Int,
        periodDays: Int = 7,
    ): Double {
        val freq = habit.minDailyFrequency
        if (freq == null || freq == 0.0) return 1.0

        val expectedCompletions = (freq / 100.0) * periodDays
        if (expectedCompletions == 0.0) return 1.0

        val ratio = completionsInPeriod.toDouble() / expectedCompletions

        // Behind target = higher reward: multiplier = 1.5 - (ratio * 0.5), clamped
        val rawMultiplier = MAX_HABIT_MULTIPLIER - ratio * 0.5
        return max(MIN_HABIT_MULTIPLIER, min(MAX_HABIT_MULTIPLIER, rawMultiplier))
    }

    fun calculateRandomMultiplier(itemId: String, timeBucket: Long): Double {
        val seed = "$itemId-$timeBucket"
        val hash = deterministicHash(seed)
        return MIN_RANDOM_MULTIPLIER + hash * (MAX_RANDOM_MULTIPLIER - MIN_RANDOM_MULTIPLIER)
    }

    fun calculateReward(
        habit: HabitEntity,
        allHabits: List<HabitEntity>,
        completionsInPeriod: Int = 0,
        timeBucket: Long = getTimeBucket(),
    ): Int {
        val difficulty = calculateDifficultyMultiplier(habit, allHabits)
        val habitMult = calculateHabitMultiplier(habit, completionsInPeriod)
        val random = calculateRandomMultiplier(habit.id, timeBucket)
        return (BASE_REWARD * difficulty * habitMult * random).roundToInt()
    }

    data class RewardBreakdown(
        val base: Int,
        val difficultyMultiplier: Double,
        val habitMultiplier: Double,
        val randomMultiplier: Double,
    )

    data class RewardWithBreakdown(
        val reward: Int,
        val breakdown: RewardBreakdown,
    )

    fun calculateRewardWithBreakdown(
        habit: HabitEntity,
        allHabits: List<HabitEntity>,
        completionsInPeriod: Int = 0,
        timeBucket: Long = getTimeBucket(),
    ): RewardWithBreakdown {
        val difficulty = calculateDifficultyMultiplier(habit, allHabits)
        val habitMult = calculateHabitMultiplier(habit, completionsInPeriod)
        val random = calculateRandomMultiplier(habit.id, timeBucket)
        val reward = (BASE_REWARD * difficulty * habitMult * random).roundToInt()
        return RewardWithBreakdown(
            reward = reward,
            breakdown = RewardBreakdown(BASE_REWARD, difficulty, habitMult, random),
        )
    }
}
