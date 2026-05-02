import Foundation
import Testing
@testable import tofustash

private func makeHabit(
    id: RecordID = "habit-1",
    frequency: Double? = nil,
    difficultyTier: HabitDifficultyTier? = nil,
    durationSeconds: Int? = nil,
    lockoutDurationSeconds: Int? = nil,
    skipConsequence: Int? = nil,
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
        difficultyTier: difficultyTier,
        durationSeconds: durationSeconds,
        lockoutDurationSeconds: lockoutDurationSeconds,
        skipConsequence: skipConsequence
    )
}

struct DifficultyMultiplierTests {
    private let tolerance = 0.0001

    // Behaviour: Tier pricing is now absolute, so a harder tier always pays
    // more than a lighter one without depending on any other habits.
    @Test func harderTiersAlwaysPayMore() {
        let trivial = makeHabit(difficultyTier: .trivial)
        let extreme = makeHabit(difficultyTier: .extreme)

        #expect(abs(RewardCalculation.calculateDifficultyMultiplier(habit: trivial) - 0.2) < tolerance)
        #expect(abs(RewardCalculation.calculateDifficultyMultiplier(habit: extreme) - 2.0) < tolerance)
    }

    // Behaviour: If the user has not picked a tier yet, pricing falls back to
    // the cheapest trivial tier so blank fields never improve payout.
    @Test func missingTierFallsBackToTrivialMultiplier() {
        let habit = makeHabit(difficultyTier: nil)
        #expect(abs(RewardCalculation.calculateDifficultyMultiplier(habit: habit) - 0.2) < tolerance)
    }
}

struct FrequencyMultiplierTests {
    // Behaviour: Leaving a habit frequency blank should price it exactly like
    // the highest selectable minimum cadence instead of a separate magic rule.
    @Test func nilFrequencyMatchesHighestConfiguredFrequency() {
        let createdAt = Date(timeIntervalSince1970: 1_577_836_800)
        let blank = makeHabit(frequency: nil, createdAt: createdAt)
        let configured = makeHabit(
            frequency: FrequencyBounds.maximumDailyRate,
            createdAt: createdAt
        )

        let blankMultiplier = RewardCalculation.calculateFrequencyMultiplier(
            habit: blank,
            completionDates: []
        )
        let configuredMultiplier = RewardCalculation.calculateFrequencyMultiplier(
            habit: configured,
            completionDates: []
        )

        #expect(blankMultiplier == configuredMultiplier)
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

struct DurationAndSkipMultiplierTests {
    // Behaviour: Longer expected effort should pay more, while the duration
    // multiplier stays within a bounded band instead of exploding linearly.
    @Test func durationRaisesRewardWithinBoundedRange() {
        let short = RewardCalculation.calculateDurationMultiplier(habit: makeHabit(durationSeconds: 300))
        let medium = RewardCalculation.calculateDurationMultiplier(habit: makeHabit(durationSeconds: 3_600))
        let long = RewardCalculation.calculateDurationMultiplier(habit: makeHabit(durationSeconds: 43_200))

        #expect(short >= 1.0)
        #expect(medium > short)
        #expect(long > medium)
        #expect(long <= 1.35)
    }

    // Behaviour: Leaving duration blank should keep the smallest duration modifier.
    @Test func missingDurationUsesNeutralMinimumMultiplier() {
        #expect(RewardCalculation.calculateDurationMultiplier(habit: makeHabit(durationSeconds: nil)) == 1.0)
    }

    // Behaviour: More serious skip consequence should make the same habit pay more.
    @Test func skipConsequenceRaisesReward() {
        let low = RewardCalculation.calculateSkipConsequenceMultiplier(habit: makeHabit(skipConsequence: 1))
        let high = RewardCalculation.calculateSkipConsequenceMultiplier(habit: makeHabit(skipConsequence: 5))

        #expect(low == 1.0)
        #expect(high > low)
    }

    // Behaviour: Leaving skip consequence blank should keep the smallest modifier.
    @Test func missingSkipConsequenceUsesNeutralMinimumMultiplier() {
        #expect(RewardCalculation.calculateSkipConsequenceMultiplier(habit: makeHabit(skipConsequence: nil)) == 1.0)
    }
}

struct CalculateRewardTests {
    // Behaviour: The user-facing reward is a deterministic whole-number tofu
    // amount with no time-bucket randomness, and habit payouts are not scaled
    // by the general difficulty setting.
    @Test func rewardUsesTierAndFrequencyWithoutRandomness() {
        let habit = makeHabit(
            frequency: 1.0,
            difficultyTier: .hard,
            durationSeconds: nil,
            skipConsequence: 1
        )

        let reward = RewardCalculation.calculateReward(
            habit: habit,
            allHabits: [habit],
            completionDates: []
        )

        #expect(reward == 280)
    }

    // Behaviour: Leaving the optional pricing fields blank should produce the
    // smallest payout instead of blocking the claim flow.
    @Test func missingFieldsUseLowestRewardFallbacks() {
        let cheapest = makeHabit(
            frequency: nil,
            difficultyTier: nil,
            durationSeconds: nil,
            skipConsequence: nil
        )
        let richer = makeHabit(
            frequency: 1.0,
            difficultyTier: .medium,
            durationSeconds: 900,
            skipConsequence: 3
        )

        let cheapReward = RewardCalculation.calculateReward(habit: cheapest, allHabits: [cheapest])
        let richerReward = RewardCalculation.calculateReward(habit: richer, allHabits: [richer])

        #expect(cheapReward < richerReward)
    }

    // Behaviour: when a habit has an active special offer, the visible payout
    // and the recorded trade amount should both use the boosted percentage.
    @Test func specialOfferRaisesHabitReward() {
        let habit = makeHabit(
            frequency: 1.0,
            difficultyTier: .medium,
            durationSeconds: 900,
            skipConsequence: 3
        )

        let baseReward = RewardCalculation.calculateReward(
            habit: habit,
            allHabits: [habit],
            completionDates: []
        )
        let boostedReward = RewardCalculation.calculateReward(
            habit: habit,
            allHabits: [habit],
            completionDates: [],
            specialOfferModifierPercent: 50
        )

        #expect(boostedReward == Int((Double(baseReward) * 1.5).rounded()))
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
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let second = RewardCalculation.calculateReward(
            habit: habit,
            allHabits: [habit],
            completionDates: [Date(timeIntervalSince1970: 2_000_000_000)],
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let total = RewardCalculation.calculateMultiPurchaseTotal(
            habit: habit,
            allHabits: [habit],
            completionDates: [],
            quantity: 2,
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )

        #expect(total == first + second)
    }
}
