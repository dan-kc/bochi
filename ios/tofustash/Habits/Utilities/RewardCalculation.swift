import Foundation

// Pure functions for calculating the tofu reward a user sees when completing a
// habit.
//
// Formula: Reward = round(100 * T * F * D * S)
//   T = fixed difficulty-tier multiplier
//   F = frequency multiplier based on completion rate, range (0, 2)
//   D = expected-effort duration multiplier
//   S = skip-consequence multiplier
enum RewardCalculation {

    // Higher values make payouts react more strongly when the user drifts away
    // from the target cadence for this habit.
    nonisolated private static let alpha = 3.75
    nonisolated private static let maxDurationSeconds = 43_200.0
    nonisolated private static let durationInfluence = 0.35

    // New habits warm up toward "on target" instead of immediately assuming
    // the user is under-performing a brand-new habit with no real history yet.
    nonisolated private static let habitNeutralRatio = 1.0

    // Difficulty is now a fixed user-chosen tier instead of a relative ranking.
    nonisolated static func calculateDifficultyMultiplier(habit: Habit) -> Double {
        habit.difficultyTier?.multiplier ?? HabitDifficultyTier.trivial.multiplier
    }

    nonisolated static func calculateFrequencyMultiplier(
        habit: Habit,
        completionDates: [Date],
        now: Date = Date()
    ) -> Double {
        let configuredRate = habit.frequency ?? FrequencyBounds.maximumDailyRate
        guard let targetSpacingDays = CadenceDecayPricing.targetSpacingDays(ratePerDay: configuredRate) else {
            return 1.0
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

    nonisolated static func calculateDurationMultiplier(habit: Habit) -> Double {
        guard let durationSeconds = habit.durationSeconds, durationSeconds > 0 else {
            return 1.0
        }

        let normalized = log1p(Double(durationSeconds)) / log1p(maxDurationSeconds)
        return 1.0 + (normalized * durationInfluence)
    }

    nonisolated static func calculateSkipConsequenceMultiplier(habit: Habit) -> Double {
        SkipConsequenceTier.from(habit.skipConsequence)?.multiplier ?? 1.0
    }

    nonisolated static func calculateReward(
        habit: Habit,
        allHabits: [Habit],
        completionDates: [Date] = [],
        now: Date = Date()
    ) -> Int {
        let difficultyMultiplier = calculateDifficultyMultiplier(habit: habit)
        let frequencyMultiplier = calculateFrequencyMultiplier(
            habit: habit,
            completionDates: completionDates,
            now: now
        )
        let durationMultiplier = calculateDurationMultiplier(habit: habit)
        let skipConsequenceMultiplier = calculateSkipConsequenceMultiplier(habit: habit)

        let reward = 100.0
            * difficultyMultiplier
            * frequencyMultiplier
            * durationMultiplier
            * skipConsequenceMultiplier
        return Int(reward.rounded())
    }

    nonisolated static func calculateMultiPurchaseTotal(
        habit: Habit,
        allHabits: [Habit],
        completionDates: [Date],
        quantity: Int,
        now: Date = Date()
    ) -> Int {
        var total = 0
        var projectedCompletionDates = completionDates

        for _ in 0..<quantity {
            total += calculateReward(
                habit: habit,
                allHabits: allHabits,
                completionDates: projectedCompletionDates,
                now: now
            )
            projectedCompletionDates.append(now)
        }
        return total
    }
}
