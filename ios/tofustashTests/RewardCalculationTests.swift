import Foundation
import Testing
@testable import tofustash

private func makeHabit(
    id: String = "habit-1",
    frequency: Double? = nil,
    difficultyTier: HabitDifficultyTier? = nil,
    createdAt: Date = Date(timeIntervalSince1970: 1_577_836_800),
    deletedAt: Date? = nil
) -> Habit {
    Habit(
        id: id,
        name: "Test Habit",
        description: "",
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: deletedAt,
        frequency: frequency,
        difficultyTier: difficultyTier
    )
}

struct DifficultyMultiplierTests {
    // Behaviour: Tier pricing is now absolute, so a harder tier always pays
    // more than a lighter one without depending on any other habits.
    @Test func harderTiersAlwaysPayMore() {
        let trivial = makeHabit(difficultyTier: .trivial)
        let extreme = makeHabit(difficultyTier: .extreme)

        #expect(RewardCalculation.calculateDifficultyMultiplier(habit: trivial) == 0.8)
        #expect(RewardCalculation.calculateDifficultyMultiplier(habit: extreme) == 1.25)
    }

    // Behaviour: If the user has not picked a tier yet, pricing falls back to
    // the neutral medium tier instead of failing.
    @Test func missingTierFallsBackToMediumMultiplier() {
        let habit = makeHabit(difficultyTier: nil)
        #expect(RewardCalculation.calculateDifficultyMultiplier(habit: habit) == 1.0)
    }
}

struct FrequencyMultiplierTests {
    // Behaviour: A habit with no target frequency keeps neutral pricing.
    @Test func nilFrequencyUsesNeutralMultiplier() {
        #expect(RewardCalculation.calculateFrequencyMultiplier(
            habit: makeHabit(frequency: nil),
            completionsInPeriod: 5
        ) == 1.0)
    }

    // Behaviour: Doing a habit less often than desired pays more than doing it
    // at or above the target rate.
    @Test func rewardFallsAsRecentCompletionsRise() {
        let habit = makeHabit(frequency: 1.0)

        let zero = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 0, periodDays: 7)
        let target = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 7, periodDays: 7)
        let above = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 14, periodDays: 7)

        #expect(zero == 2.0)
        #expect(target == 1.0)
        #expect(above < 1.0)
    }
}

struct CalculateRewardTests {
    // Behaviour: The user-facing reward is a deterministic whole-number tofu
    // amount with no time-bucket randomness.
    @Test func rewardUsesTierAndFrequencyWithoutRandomness() {
        let habit = makeHabit(frequency: 1.0, difficultyTier: .hard)

        let reward = RewardCalculation.calculateReward(
            habit: habit,
            allHabits: [habit],
            completionsInPeriod: 0,
            generalDifficulty: 5
        )

        #expect(reward == 1_100)
    }

    // Behaviour: The app explains exactly which required habit inputs are still
    // missing before the user can claim tofu.
    @Test func missingTradePropertiesDescribesIncompleteSetup() {
        #expect(RewardCalculation.missingTradeProperties(frequency: nil, difficultyTier: nil) == "frequency and difficulty")
        #expect(RewardCalculation.missingTradeProperties(frequency: nil, difficultyTier: .medium) == "frequency")
        #expect(RewardCalculation.missingTradeProperties(frequency: 1.0, difficultyTier: nil) == "difficulty")
        #expect(RewardCalculation.missingTradeProperties(frequency: 1.0, difficultyTier: .medium) == nil)
    }
}

struct MultiPurchaseTotalTests {
    // Behaviour: Claiming a habit multiple times in one modal sums each
    // incremental payout, so repeated claims reflect diminishing returns.
    @Test func multiClaimMatchesIncrementalPrices() {
        let habit = makeHabit(frequency: 1.0, difficultyTier: .medium)

        let first = RewardCalculation.calculateReward(
            habit: habit,
            allHabits: [habit],
            completionsInPeriod: 0,
            generalDifficulty: 5
        )
        let second = RewardCalculation.calculateReward(
            habit: habit,
            allHabits: [habit],
            completionsInPeriod: 1,
            generalDifficulty: 5
        )
        let total = RewardCalculation.calculateMultiPurchaseTotal(
            habit: habit,
            allHabits: [habit],
            currentCompletions: 0,
            quantity: 2,
            generalDifficulty: 5
        )

        #expect(total == first + second)
    }
}
