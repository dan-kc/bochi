import Foundation

// Pure functions for the static task reward formula.
//
// Formula: Reward = round(100 * T * D * S)
//   T = difficulty tier multiplier
//   D = duration multiplier
//   S = skip-consequence multiplier
enum TaskRewardCalculation {
    nonisolated private static let maxDurationSeconds = 43_200.0
    nonisolated private static let durationInfluence = 0.35

    nonisolated static func calculateDifficultyMultiplier(task: TaskItem) -> Double {
        task.difficultyTier?.multiplier ?? HabitDifficultyTier.trivial.multiplier
    }

    nonisolated static func calculateDurationMultiplier(task: TaskItem) -> Double {
        guard let durationSeconds = task.durationSeconds, durationSeconds > 0 else {
            return 1.0
        }

        let normalized = log1p(Double(durationSeconds)) / log1p(maxDurationSeconds)
        return 1.0 + (normalized * durationInfluence)
    }

    nonisolated static func calculateSkipConsequenceMultiplier(task: TaskItem) -> Double {
        SkipConsequenceTier.from(task.skipConsequence)?.multiplier ?? 1.0
    }

    nonisolated static func calculateReward(
        task: TaskItem,
        specialOfferModifierPercent: Int? = nil
    ) -> Int {
        let reward = 100.0
            * calculateDifficultyMultiplier(task: task)
            * calculateDurationMultiplier(task: task)
            * calculateSkipConsequenceMultiplier(task: task)
        return SpecialOfferSupport.adjustedAmount(
            baseAmount: Int(reward.rounded()),
            specialOfferModifierPercent: specialOfferModifierPercent
        )
    }
}
