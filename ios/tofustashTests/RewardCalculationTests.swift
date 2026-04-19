import Foundation
import Testing
@testable import tofustash

private func makeHabit(
    id: RecordID = "habit-1",
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
            completionDates: []
        ) == 1.0)
    }

    // Behaviour: Equivalent rates should stabilize the same way even if the
    // user picked different UI units such as `1/day` or `30/month`.
    @Test func equivalentRatesShareTheSameCadenceModel() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let createdAt = now.addingTimeInterval(-10 * 86_400)
        let dailyHabit = makeHabit(frequency: 1.0, createdAt: createdAt)
        let monthlyHabit = makeHabit(frequency: 30.0 / 30.0, createdAt: createdAt)
        let completionDates = [now.addingTimeInterval(-86_400)]

        let daily = RewardCalculation.calculateFrequencyMultiplier(
            habit: dailyHabit,
            completionDates: completionDates,
            now: now
        )
        let monthly = RewardCalculation.calculateFrequencyMultiplier(
            habit: monthlyHabit,
            completionDates: completionDates,
            now: now
        )

        #expect(abs(daily - monthly) < 0.0001)
    }

    // Behaviour: A newly created habit should not jump straight to the maximum
    // payout before the app has enough history to judge the user's cadence.
    @Test func newHabitStartsNearNeutralDuringWarmup() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let newHabit = makeHabit(
            frequency: 1.0,
            createdAt: now.addingTimeInterval(-6 * 3_600)
        )

        let multiplier = RewardCalculation.calculateFrequencyMultiplier(
            habit: newHabit,
            completionDates: [],
            now: now
        )

        #expect(multiplier > 1.0)
        #expect(multiplier < 2.0)
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
            completionDates: [],
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
            completionDates: [],
            now: Date(timeIntervalSince1970: 2_000_000_000),
            generalDifficulty: 5
        )
        let second = RewardCalculation.calculateReward(
            habit: habit,
            allHabits: [habit],
            completionDates: [Date(timeIntervalSince1970: 2_000_000_000)],
            now: Date(timeIntervalSince1970: 2_000_000_000),
            generalDifficulty: 5
        )
        let total = RewardCalculation.calculateMultiPurchaseTotal(
            habit: habit,
            allHabits: [habit],
            completionDates: [],
            quantity: 2,
            now: Date(timeIntervalSince1970: 2_000_000_000),
            generalDifficulty: 5
        )

        #expect(total == first + second)
    }
}
