import Foundation

// Pure functions for calculating the tofu reward a user sees when completing a
// habit.
//
// Formula: Reward = round(100 * G * T * F)
//   G = general difficulty (user-configurable scalar, default 5.0)
//   T = fixed difficulty-tier multiplier
//   F = frequency multiplier based on completion rate, range (0, 2)
enum RewardCalculation {

    // Higher values make rewards fall off faster once the user exceeds the
    // target completion rate for a habit.
    nonisolated private static let alpha = 2.5

    // New habits warm up toward "on target" instead of immediately assuming
    // the user is under-performing a brand-new habit with no real history yet.
    nonisolated private static let habitNeutralRatio = 1.0

    // Difficulty is now a fixed user-chosen tier instead of a relative ranking.
    nonisolated static func calculateDifficultyMultiplier(habit: Habit) -> Double {
        habit.difficultyTier?.multiplier ?? HabitDifficultyTier.medium.multiplier
    }

    nonisolated static func calculateFrequencyMultiplier(
        habit: Habit,
        completionDates: [Date],
        now: Date = Date()
    ) -> Double {
        guard let targetSpacingDays = CadenceDecayPricing.targetSpacingDays(ratePerDay: habit.frequency) else {
            return 1
        }

        let rawRatio = CadenceDecayPricing.normalizedUsageRatio(
            eventDates: completionDates,
            targetSpacingDays: targetSpacingDays,
            now: now
        )
        let effectiveRatio = CadenceDecayPricing.blendedUsageRatio(
            rawRatio: rawRatio,
            createdAt: habit.createdAt,
            targetSpacingDays: targetSpacingDays,
            neutralRatio: habitNeutralRatio,
            now: now
        )

        return 2.0 / (1.0 + pow(effectiveRatio, alpha))
    }

    nonisolated static func calculateReward(
        habit: Habit,
        allHabits: [Habit],
        completionDates: [Date] = [],
        now: Date = Date(),
        generalDifficulty: Double = 5.0
    ) -> Int {
        let difficultyMultiplier = calculateDifficultyMultiplier(habit: habit)
        let frequencyMultiplier = calculateFrequencyMultiplier(
            habit: habit,
            completionDates: completionDates,
            now: now
        )

        let reward = 100.0 * generalDifficulty * difficultyMultiplier * frequencyMultiplier
        return Int(reward.rounded())
    }

    // Human-readable reason the trade action is blocked.
    nonisolated static func missingTradeProperties(
        frequency: Double?,
        difficultyTier: HabitDifficultyTier?
    ) -> String? {
        switch (frequency == nil, difficultyTier == nil) {
        case (true, true): return "frequency and difficulty"
        case (true, false): return "frequency"
        case (false, true): return "difficulty"
        case (false, false): return nil
        }
    }

    nonisolated static func calculateMultiPurchaseTotal(
        habit: Habit,
        allHabits: [Habit],
        completionDates: [Date],
        quantity: Int,
        now: Date = Date(),
        generalDifficulty: Double = 5.0
    ) -> Int {
        var total = 0
        var projectedCompletionDates = completionDates

        for _ in 0..<quantity {
            total += calculateReward(
                habit: habit,
                allHabits: allHabits,
                completionDates: projectedCompletionDates,
                now: now,
                generalDifficulty: generalDifficulty
            )
            projectedCompletionDates.append(now)
        }
        return total
    }
}
