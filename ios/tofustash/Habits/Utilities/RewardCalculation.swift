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

    // The neutral completion ratio used as a fallback when age blending
    // is in effect. At ratio 1.0, the frequency multiplier F equals 1.0.
    nonisolated private static let habitNeutralRatio = 1.0

    // Difficulty is now a fixed user-chosen tier instead of a relative ranking.
    nonisolated static func calculateDifficultyMultiplier(habit: Habit) -> Double {
        habit.difficultyTier?.multiplier ?? HabitDifficultyTier.medium.multiplier
    }

    nonisolated static func calculateFrequencyMultiplier(
        habit: Habit,
        completionsInPeriod: Int,
        periodDays: Int = 7
    ) -> Double {
        guard let frequency = habit.frequency, frequency != 0 else {
            return 1
        }

        let expectedCompletions = frequency * Double(periodDays)
        guard expectedCompletions != 0 else {
            return 1
        }

        let r = Double(completionsInPeriod) / expectedCompletions
        let rEff = r

        return 2.0 / (1.0 + pow(rEff, alpha))
    }

    nonisolated static func calculateReward(
        habit: Habit,
        allHabits: [Habit],
        completionsInPeriod: Int = 0,
        generalDifficulty: Double = 5.0
    ) -> Int {
        let difficultyMultiplier = calculateDifficultyMultiplier(habit: habit)
        let frequencyMultiplier = calculateFrequencyMultiplier(
            habit: habit,
            completionsInPeriod: completionsInPeriod
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
        currentCompletions: Int,
        quantity: Int,
        generalDifficulty: Double = 5.0
    ) -> Int {
        var total = 0
        for i in 0..<quantity {
            total += calculateReward(
                habit: habit,
                allHabits: allHabits,
                completionsInPeriod: currentCompletions + i,
                generalDifficulty: generalDifficulty
            )
        }
        return total
    }
}
