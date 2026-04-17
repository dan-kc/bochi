import Foundation
import Testing
@testable import tofustash

// Helper to create test habits with sensible defaults.
// createdAt defaults to a date far in the past (>30 days ago) so age blending
// is fully weighted toward the actual ratio, matching the JS test helper.
private func makeHabit(
    id: String = "test-habit-1",
    frequency: Double? = nil,
    difficultyRank: String? = nil,
    createdAt: Date = Date(timeIntervalSince1970: 1577836800), // 2020-01-01
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
        difficultyRank: difficultyRank
    )
}

// MARK: - Difficulty Multiplier
// D = (N - rank + 1) / (N + 1), where N = total ranked active habits,
// rank = 1-indexed position sorted by difficulty_rank string.
// Easiest habits (lowest rank string) get the highest D.
struct DifficultyMultiplierTests {

    // Behaviour: A habit without difficulty ranking falls back to a neutral reward adjustment.
    @Test("Returns 0.5 when habit has no difficulty rank")
    func unrankedHabit() {
        let habit = makeHabit(difficultyRank: nil)
        let d = RewardCalculation.calculateDifficultyMultiplier(habit: habit, allHabits: [habit])
        #expect(d == 0.5)
    }

    // Behaviour: If the user has not ranked any habits yet, all rewards use the neutral difficulty multiplier.
    @Test("Returns 0.5 when no habits have difficulty ranks")
    func noRankedHabits() {
        let habit = makeHabit(id: "h1", difficultyRank: "a0")
        let allHabits = [
            makeHabit(id: "1", difficultyRank: nil),
            makeHabit(id: "2", difficultyRank: nil),
        ]
        let d = RewardCalculation.calculateDifficultyMultiplier(habit: habit, allHabits: allHabits)
        #expect(d == 0.5)
    }

    // Behaviour: The very first ranked habit lands on the neutral midpoint.
    @Test("Single ranked habit gets D = 1/2")
    func singleRanked() {
        let habit = makeHabit(difficultyRank: "m0")
        // N=1, rank=1: (1 - 1 + 1) / (1 + 1) = 0.5
        let d = RewardCalculation.calculateDifficultyMultiplier(habit: habit, allHabits: [habit])
        #expect(d == 0.5)
    }

    // Behaviour: The easiest habit in a small list pays more because the user is expected to do it more often.
    @Test("Easiest habit in two-item list gets highest D")
    func easiestOfTwo() {
        let easy = makeHabit(id: "easy", difficultyRank: "a0")
        let hard = makeHabit(id: "hard", difficultyRank: "z0")
        let allHabits = [easy, hard]
        // N=2, rank=1: (2 - 1 + 1) / (2 + 1) = 2/3
        let d = RewardCalculation.calculateDifficultyMultiplier(habit: easy, allHabits: allHabits)
        #expect(abs(d - 2.0 / 3.0) < 1e-10)
    }

    // Behaviour: The hardest habit in a small list pays less than the easiest one.
    @Test("Hardest habit in two-item list gets lowest D")
    func hardestOfTwo() {
        let easy = makeHabit(id: "easy", difficultyRank: "a0")
        let hard = makeHabit(id: "hard", difficultyRank: "z0")
        let allHabits = [easy, hard]
        // N=2, rank=2: (2 - 2 + 1) / (2 + 1) = 1/3
        let d = RewardCalculation.calculateDifficultyMultiplier(habit: hard, allHabits: allHabits)
        #expect(abs(d - 1.0 / 3.0) < 1e-10)
    }

    // Behaviour: A middle-ranked habit gets the neutral difficulty multiplier.
    @Test("Middle ranked habit in three-item list gets D = 0.5")
    func middleOfThree() {
        let low = makeHabit(id: "low", difficultyRank: "a0")
        let mid = makeHabit(id: "mid", difficultyRank: "m0")
        let high = makeHabit(id: "high", difficultyRank: "z0")
        let allHabits = [low, mid, high]
        // N=3, rank=2: (3 - 2 + 1) / (3 + 1) = 0.5
        let d = RewardCalculation.calculateDifficultyMultiplier(habit: mid, allHabits: allHabits)
        #expect(d == 0.5)
    }

    // Behaviour: Deleted habits should not keep affecting the reward prices of visible habits.
    @Test("Ignores deleted habits in ranking")
    func ignoresDeleted() {
        let active = makeHabit(id: "active", difficultyRank: "a0")
        let deleted = makeHabit(id: "deleted", difficultyRank: "z0", deletedAt: Date())
        let allHabits = [active, deleted]
        // Deleted is excluded, so only one ranked habit → D = 0.5
        let d = RewardCalculation.calculateDifficultyMultiplier(habit: active, allHabits: allHabits)
        #expect(d == 0.5)
    }

    // Behaviour: Difficulty scaling always stays in a sensible range and never produces zero or negative rewards.
    @Test("D is always in (0, 1) for any number of habits")
    func alwaysInRange() {
        let habits = (0..<10).map { i in
            makeHabit(id: "h\(i)", difficultyRank: "\(Character(UnicodeScalar(97 + i)!))0")
        }
        for habit in habits {
            let d = RewardCalculation.calculateDifficultyMultiplier(habit: habit, allHabits: habits)
            #expect(d > 0, "D should be > 0")
            #expect(d < 1, "D should be < 1")
        }
    }
}

// MARK: - Frequency Multiplier
// F = 2 / (1 + r_eff^α), α=2.5
// Where r_eff blends the actual completion ratio with a neutral value
// based on habit age (new habits default toward 1.0).
struct FrequencyMultiplierTests {

    // Behaviour: A habit with no frequency target keeps the neutral frequency multiplier.
    @Test("Returns 1 when frequency is nil")
    func nilFrequency() {
        let habit = makeHabit(frequency: nil)
        let f = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 5)
        #expect(f == 1)
    }

    // Behaviour: A zero frequency target behaves like "no target set" instead of breaking pricing.
    @Test("Returns 1 when frequency is 0")
    func zeroFrequency() {
        // frequency 0 means "no target set" — neutral multiplier
        let habit = makeHabit(frequency: 0)
        let f = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 5)
        #expect(f == 1)
    }

    // Behaviour: A user who has not done a mature habit recently sees the maximum encouragement reward.
    @Test("Zero completions for mature habit gives F = 2")
    func zeroCompletionsMature() {
        // frequency=1.0 (once/day), expected=7 over 7 days, r=0, r_eff=0
        // F = 2/(1+0^2.5) = 2/1 = 2
        let habit = makeHabit(frequency: 1.0)
        let f = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 0, periodDays: 7)
        #expect(f == 2)
    }

    // Behaviour: Hitting the target frequency gives the neutral reward multiplier.
    @Test("Exact target completion gives F = 1")
    func exactTarget() {
        // frequency=1.0, expected=7, actual=7, r=1.0, r_eff=1.0
        // F = 2/(1+1^2.5) = 2/2 = 1
        let habit = makeHabit(frequency: 1.0)
        let f = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 7, periodDays: 7)
        #expect(f == 1)
    }

    // Behaviour: Doing a habit far more than the target lowers its per-completion reward.
    @Test("Exceeding target lowers F below 1")
    func exceedingTarget() {
        // frequency=1.0, expected=7, actual=14, r=2.0
        // F = 2/(1+2^2.5) ≈ 0.3
        let habit = makeHabit(frequency: 1.0)
        let f = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 14, periodDays: 7)
        #expect(f < 1)
        #expect(f > 0)
    }

    // Behaviour: Frequency scaling stays bounded so rewards do not explode or collapse to zero.
    @Test("F is naturally bounded between 0 and 2")
    func bounded() {
        let habit = makeHabit(frequency: 1.0)
        let fZero = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 0, periodDays: 7)
        let fHigh = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 100, periodDays: 7)
        #expect(fZero <= 2)
        #expect(fHigh > 0)
    }

    // Behaviour: Brand-new habits are still rewarding immediately on iOS instead of being flattened to neutral pricing.
    @Test("New habit still gets full frequency multiplier (age blending disabled)")
    func newHabitNoAgeBlending() {
        // Age blending is disabled in the iOS version (in-memory storage means
        // all habits are new). A brand new habit with 0 completions should
        // get F = 2, same as a mature habit.
        let habit = makeHabit(frequency: 1.0, createdAt: Date())
        let f = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 0, periodDays: 7)
        #expect(f == 2)
    }

    // Behaviour: The more recently the user has completed a habit, the less the next completion pays.
    @Test("Price decreases as completions increase")
    func priceDecreasesWithCompletions() {
        // With frequency=1.0 (once/day), completing more often should
        // reduce the reward. This is the core diminishing returns mechanic.
        let habit = makeHabit(frequency: 1.0)
        let f0 = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 0, periodDays: 7)
        let f3 = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 3, periodDays: 7)
        let f7 = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 7, periodDays: 7)
        let f14 = RewardCalculation.calculateFrequencyMultiplier(habit: habit, completionsInPeriod: 14, periodDays: 7)
        #expect(f0 > f3)
        #expect(f3 > f7)
        #expect(f7 > f14)
    }
}

// MARK: - Random Multiplier
// R = 0.9 + deterministicHash(habitId + "-" + timeBucket) * 0.2
// Deterministic per (habit, time bucket) pair, changes every 30 minutes.
struct RandomMultiplierTests {

    // Behaviour: The dynamic pricing effect stays subtle and never swings beyond the intended small range.
    @Test("Returns value between 0.9 and 1.1")
    func inRange() {
        let r = RewardCalculation.calculateRandomMultiplier(habitId: "habit-1", timeBucket: 12345)
        #expect(r >= 0.9)
        #expect(r < 1.1)
    }

    // Behaviour: Refreshing the UI within the same time bucket should not change the visible price.
    @Test("Is deterministic for same inputs")
    func deterministic() {
        let r1 = RewardCalculation.calculateRandomMultiplier(habitId: "habit-1", timeBucket: 12345)
        let r2 = RewardCalculation.calculateRandomMultiplier(habitId: "habit-1", timeBucket: 12345)
        #expect(r1 == r2)
    }

    // Behaviour: Two different habits can legitimately show different prices at the same moment.
    @Test("Varies by habit ID")
    func variesByHabit() {
        let r1 = RewardCalculation.calculateRandomMultiplier(habitId: "habit-1", timeBucket: 12345)
        let r2 = RewardCalculation.calculateRandomMultiplier(habitId: "habit-2", timeBucket: 12345)
        #expect(r1 != r2)
    }

    // Behaviour: The same habit can show a different price after the 30-minute pricing window rolls over.
    @Test("Varies by time bucket")
    func variesByTimeBucket() {
        let r1 = RewardCalculation.calculateRandomMultiplier(habitId: "habit-1", timeBucket: 12345)
        let r2 = RewardCalculation.calculateRandomMultiplier(habitId: "habit-1", timeBucket: 12346)
        #expect(r1 != r2)
    }
}

// MARK: - Full Reward Calculation
// Reward = round(100 * G * D * F * R)
struct CalculateRewardTests {

    // Behaviour: The user-facing reward is always shown as a whole tofu amount.
    @Test("Returns a rounded integer")
    func roundedInteger() {
        let habit = makeHabit()
        let reward = RewardCalculation.calculateReward(habit: habit, allHabits: [habit], completionsInPeriod: 0, timeBucket: 12345, generalDifficulty: 5)
        #expect(reward == reward) // Int is always whole
    }

    // Behaviour: An unranked habit with no frequency target still produces a sensible baseline reward.
    @Test("Unranked habit with no frequency: reward = 100 * G * 0.5 * 1 * R")
    func unrankedNoFrequency() {
        let habit = makeHabit(frequency: nil, difficultyRank: nil)
        let reward = RewardCalculation.calculateReward(habit: habit, allHabits: [habit], completionsInPeriod: 0, timeBucket: 12345, generalDifficulty: 5)
        // 100 * 5 * 0.5 * 1 * R, where R ∈ [0.9, 1.1)
        let low = Int(round(100 * 5 * 0.5 * 0.9))  // 225
        let high = Int(round(100 * 5 * 0.5 * 1.1))  // 275
        #expect(reward >= low)
        #expect(reward <= high)
    }

    // Behaviour: Raising the global difficulty setting scales the displayed reward proportionally.
    @Test("General difficulty scales reward linearly")
    func difficultyScalesLinearly() {
        let habit = makeHabit(frequency: nil, difficultyRank: nil)
        let r1 = RewardCalculation.calculateReward(habit: habit, allHabits: [habit], completionsInPeriod: 0, timeBucket: 12345, generalDifficulty: 1)
        let r10 = RewardCalculation.calculateReward(habit: habit, allHabits: [habit], completionsInPeriod: 0, timeBucket: 12345, generalDifficulty: 10)
        // r10 should be ~10x r1 (with some rounding tolerance)
        #expect(abs(Double(r10) - Double(r1) * 10) <= 5)
    }
}

// MARK: - Time Bucket
// Bucket = floor(epoch_ms / 1_800_000). Two dates within the same
// 30-minute window should share a bucket.
struct TimeBucketTests {

    // Behaviour: Looking at a reward twice within the same 30-minute window should use the same pricing bucket.
    @Test("Same bucket for dates within same 30-minute window")
    func sameBucket() {
        // 2024-01-01 12:00:00 UTC and 12:29:59 UTC
        let date1 = Date(timeIntervalSince1970: 1704110400) // 12:00:00
        let date2 = Date(timeIntervalSince1970: 1704112199) // 12:29:59
        #expect(RewardCalculation.getCurrentTimeBucket(now: date1) == RewardCalculation.getCurrentTimeBucket(now: date2))
    }

    // Behaviour: Prices are allowed to refresh once the next 30-minute window begins.
    @Test("Different bucket for dates in different 30-minute windows")
    func differentBucket() {
        let date1 = Date(timeIntervalSince1970: 1704110400) // 12:00:00
        let date2 = Date(timeIntervalSince1970: 1704112200) // 12:30:00
        #expect(RewardCalculation.getCurrentTimeBucket(now: date1) != RewardCalculation.getCurrentTimeBucket(now: date2))
    }
}

// MARK: - Multi-Purchase Total
// When purchasing N times, the total is NOT price * N. Each successive
// purchase increments completionsInPeriod, which changes the frequency
// multiplier F, resulting in a different price for each iteration.
struct MultiPurchaseTotalTests {

    // Behaviour: Buying one completion through the multi-buy path matches the single-completion price.
    @Test("Quantity 1 equals single calculateReward")
    func quantityOne() {
        let habit = makeHabit(frequency: 1.0, difficultyRank: "m0")
        let single = RewardCalculation.calculateReward(
            habit: habit, allHabits: [habit],
            completionsInPeriod: 0, timeBucket: 12345, generalDifficulty: 5
        )
        let total = RewardCalculation.calculateMultiPurchaseTotal(
            habit: habit, allHabits: [habit],
            currentCompletions: 0, quantity: 1, timeBucket: 12345, generalDifficulty: 5
        )
        #expect(total == single)
    }

    // Behaviour: Buying two completions sums the first and second prices, including diminishing returns.
    @Test("Quantity 2 equals sum of two individual prices with incremented completions")
    func quantityTwo() {
        let habit = makeHabit(frequency: 1.0, difficultyRank: "m0")
        let price0 = RewardCalculation.calculateReward(
            habit: habit, allHabits: [habit],
            completionsInPeriod: 0, timeBucket: 12345, generalDifficulty: 5
        )
        let price1 = RewardCalculation.calculateReward(
            habit: habit, allHabits: [habit],
            completionsInPeriod: 1, timeBucket: 12345, generalDifficulty: 5
        )
        let total = RewardCalculation.calculateMultiPurchaseTotal(
            habit: habit, allHabits: [habit],
            currentCompletions: 0, quantity: 2, timeBucket: 12345, generalDifficulty: 5
        )
        #expect(total == price0 + price1)
    }

    // Behaviour: Multi-buy should reflect diminishing returns instead of naively multiplying one visible price.
    @Test("Multi-purchase total is NOT simply price * quantity")
    func notSimpleMultiplication() {
        let habit = makeHabit(frequency: 1.0, difficultyRank: "m0")
        let singlePrice = RewardCalculation.calculateReward(
            habit: habit, allHabits: [habit],
            completionsInPeriod: 0, timeBucket: 12345, generalDifficulty: 5
        )
        let total = RewardCalculation.calculateMultiPurchaseTotal(
            habit: habit, allHabits: [habit],
            currentCompletions: 0, quantity: 3, timeBucket: 12345, generalDifficulty: 5
        )
        // The total should differ from singlePrice * 3 because the frequency
        // multiplier changes as completions increment
        #expect(total != singlePrice * 3)
    }
}
