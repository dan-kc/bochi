import Foundation

// Pure functions for calculating the tofu reward a user sees when completing a
// habit. Keeping this logic pure makes it easy to test and to keep iOS aligned
// with the web implementation.
//
// Formula: Reward = round(100 * G * D * F * R)
//   G = general difficulty (user-configurable scalar, default 5.0)
//   D = difficulty multiplier based on rank position, range (0, 1)
//   F = frequency multiplier based on completion rate, range (0, 2)
//   R = deterministic random multiplier, range [0.9, 1.1)
//
// Caseless enum = namespace (can't be instantiated). Like a TS module
// that only exports functions. Matches the FrequencyConversion pattern.
enum RewardCalculation {

    // MARK: - Constants

    // Higher values make rewards fall off faster once the user exceeds the
    // target completion rate for a habit.
    private static let alpha = 2.5

    // The neutral completion ratio used as a fallback when age blending
    // is in effect. At ratio 1.0, the frequency multiplier F equals 1.0.
    private static let habitNeutralRatio = 1.0

    // Time bucket size in milliseconds (30 minutes). The random multiplier R
    // changes every 30 minutes, so prices fluctuate slightly throughout the day.
    private static let timeBucketMs = 30 * 60 * 1000

    // MARK: - Difficulty Multiplier

    // Difficulty multiplier: easier habits earn slightly more because the user
    // is expected to complete them more often.
    // Formula: D = (N - rank + 1) / (N + 1)
    //
    // Habits are sorted by their difficulty_rank string (lexicographic order).
    // Lower rank strings = easier habits = higher D (more reward per completion).
    // This compensates for the fact that easier habits are done more frequently.
    //
    // Returns 0.5 if the habit is unranked or there are no ranked habits.
    static func calculateDifficultyMultiplier(habit: Habit, allHabits: [Habit]) -> Double {
        let rankedHabits = allHabits
            .filter { $0.difficultyRank != nil && $0.deletedAt == nil }
            .sorted { $0.difficultyRank! < $1.difficultyRank! }

        guard !rankedHabits.isEmpty, habit.difficultyRank != nil else {
            return 0.5
        }

        guard let position = rankedHabits.firstIndex(where: { $0.id == habit.id }) else {
            return 0.5
        }

        let n = Double(rankedHabits.count)
        let rank = Double(position + 1) // 1-indexed
        return (n - rank + 1) / (n + 1)
    }

    // MARK: - Frequency Multiplier

    // Frequency multiplier: habits pay more when the user is below target and
    // less when they are already over-performing that habit.
    //
    // Formula: F = 2 / (1 + r_eff^α), α = 2.5
    //   r = completionsInPeriod / expectedCompletions
    //   r_eff = w * r + (1 - w) * 1.0  (age-blended ratio)
    //   w = min(1, ageDays / 30)
    //
    // The result is a sigmoid-like curve:
    //   - r_eff = 0 → F = 2 (doing nothing = max reward to encourage starting)
    //   - r_eff = 1 → F = 1 (meeting target = neutral)
    //   - r_eff > 1 → F < 1 (exceeding target = diminishing returns)
    //
    // The iOS `frequency` field is already in "times per day" units (e.g., 1.0 = daily),
    // unlike the frontend's `min_daily_frequency` which is a percentage (100 = daily).
    // So expectedCompletions = frequency * periodDays (no division by 100 needed).
    static func calculateFrequencyMultiplier(
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

        // The web app blends new habits toward a neutral multiplier for their
        // first 30 days. iOS skips that for now because local persistence is not
        // in place yet; otherwise every session would look like a brand-new habit
        // and prices would barely react to completions.
        let rEff = r

        return 2.0 / (1.0 + pow(rEff, alpha))
    }

    // MARK: - Random Multiplier

    // Random-looking multiplier: stable within one 30-minute bucket so the
    // visible price does not jitter on every re-render, but it changes across
    // buckets to keep the market feeling alive.
    static func calculateRandomMultiplier(habitId: String, timeBucket: Int) -> Double {
        let seed = "\(habitId)-\(timeBucket)"
        let hash = DeterministicHash.hash(seed)
        return 0.9 + hash * 0.2
    }

    // MARK: - Time Bucket

    // Shared time bucket calculation keeps the same habit price in sync across
    // clients at the same moment.
    static func getCurrentTimeBucket(now: Date = Date()) -> Int {
        let epochMs = Int(now.timeIntervalSince1970 * 1000)
        return epochMs / timeBucketMs
    }

    // MARK: - Full Reward Calculation

    // Final user-visible reward for one completion.
    static func calculateReward(
        habit: Habit,
        allHabits: [Habit],
        completionsInPeriod: Int = 0,
        timeBucket: Int = getCurrentTimeBucket(),
        generalDifficulty: Double = 5.0
    ) -> Int {
        let d = calculateDifficultyMultiplier(habit: habit, allHabits: allHabits)
        let f = calculateFrequencyMultiplier(habit: habit, completionsInPeriod: completionsInPeriod)
        let r = calculateRandomMultiplier(habitId: habit.id, timeBucket: timeBucket)

        let reward = 100.0 * generalDifficulty * d * f * r
        return Int(reward.rounded())
    }

    // Human-readable reason the trade action is blocked.
    static func missingTradeProperties(frequency: Double?, difficultyRank: String?) -> String? {
        switch (frequency == nil, difficultyRank == nil) {
        case (true, true): return "frequency and difficulty"
        case (true, false): return "frequency"
        case (false, true): return "difficulty"
        case (false, false): return nil
        }
    }

    // MARK: - Time Bucket Helpers

    // Used by price observers so the UI can refresh exactly when the next
    // bucket begins instead of polling constantly.
    static func nanosUntilNextBucket(now: Date = Date()) -> UInt64 {
        let epochMs = now.timeIntervalSince1970 * 1000
        let bucketMs = Double(timeBucketMs)
        let msIntoCurrentBucket = epochMs.truncatingRemainder(dividingBy: bucketMs)
        let msUntilNext = bucketMs - msIntoCurrentBucket
        return UInt64((msUntilNext + 100) * 1_000_000)
    }

    // MARK: - Multi-Purchase Total

    // Multi-complete trades are summed one completion at a time because the
    // visible price should fall as the quantity increases.
    static func calculateMultiPurchaseTotal(
        habit: Habit,
        allHabits: [Habit],
        currentCompletions: Int,
        quantity: Int,
        timeBucket: Int = getCurrentTimeBucket(),
        generalDifficulty: Double = 5.0
    ) -> Int {
        var total = 0
        for i in 0..<quantity {
            total += calculateReward(
                habit: habit,
                allHabits: allHabits,
                completionsInPeriod: currentCompletions + i,
                timeBucket: timeBucket,
                generalDifficulty: generalDifficulty
            )
        }
        return total
    }
}
