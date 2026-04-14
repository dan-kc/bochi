import Foundation

// Pure functions for calculating habit reward amounts.
// Port of frontend/lib/rewardCalculation.ts.
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

    // Exponent for the frequency sigmoid curve. Higher = steeper drop-off
    // when the user exceeds their target completion rate.
    private static let alpha = 2.5

    // The neutral completion ratio used as a fallback when age blending
    // is in effect. At ratio 1.0, the frequency multiplier F equals 1.0.
    private static let habitNeutralRatio = 1.0

    // Time bucket size in milliseconds (30 minutes). The random multiplier R
    // changes every 30 minutes, so prices fluctuate slightly throughout the day.
    private static let timeBucketMs = 30 * 60 * 1000

    // MARK: - Difficulty Multiplier

    // Calculates D based on where this habit ranks among all ranked active habits.
    // Formula: D = (N - rank + 1) / (N + 1)
    //
    // Habits are sorted by their difficulty_rank string (lexicographic order).
    // Lower rank strings = easier habits = higher D (more reward per completion).
    // This compensates for the fact that easier habits are done more frequently.
    //
    // Returns 0.5 if the habit is unranked or there are no ranked habits.
    static func calculateDifficultyMultiplier(habit: Habit, allHabits: [Habit]) -> Double {
        // Filter to active, ranked habits and sort by rank string.
        // Like .filter().sort() in JS — Swift's sorted(by:) returns a new array.
        let rankedHabits = allHabits
            .filter { $0.difficultyRank != nil && $0.deletedAt == nil }
            .sorted { $0.difficultyRank! < $1.difficultyRank! }

        guard !rankedHabits.isEmpty, habit.difficultyRank != nil else {
            return 0.5
        }

        // .firstIndex(where:) is like .findIndex() in JS
        guard let position = rankedHabits.firstIndex(where: { $0.id == habit.id }) else {
            return 0.5
        }

        let n = Double(rankedHabits.count)
        let rank = Double(position + 1) // 1-indexed
        return (n - rank + 1) / (n + 1)
    }

    // MARK: - Frequency Multiplier

    // Calculates F based on how often the user actually completes the habit
    // relative to their target frequency.
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

        // Note: The frontend has age blending that dampens the frequency
        // multiplier for habits less than 30 days old (r_eff blends toward
        // 1.0 for new habits). This is disabled in the iOS version because
        // the app currently uses in-memory storage — all habits are "brand
        // new" every session, which would make F ≈ 1.0 always and prevent
        // prices from ever changing with completions. Age blending should
        // be re-enabled when persistence is added.
        let rEff = r

        return 2.0 / (1.0 + pow(rEff, alpha))
    }

    // MARK: - Random Multiplier

    // Calculates R — a deterministic "random" multiplier that varies slightly
    // by habit and time bucket. Range: [0.9, 1.1).
    //
    // The same (habitId, timeBucket) pair always produces the same R. This means
    // the price is stable within each 30-minute window but shifts slightly every
    // half hour, adding a sense of dynamic pricing without true randomness.
    static func calculateRandomMultiplier(habitId: String, timeBucket: Int) -> Double {
        let seed = "\(habitId)-\(timeBucket)"
        let hash = DeterministicHash.hash(seed)
        return 0.9 + hash * 0.2
    }

    // MARK: - Time Bucket

    // Returns the current time bucket — a 30-minute interval since Unix epoch.
    // All clients sharing the same formula will compute the same bucket at any
    // given moment, ensuring price consistency across platforms.
    //
    // now parameter is injectable for testing (like the JS version's default arg).
    static func getCurrentTimeBucket(now: Date = Date()) -> Int {
        // Date's timeIntervalSince1970 returns seconds (Double). Multiply by
        // 1000 to get milliseconds to match the JS formula.
        let epochMs = Int(now.timeIntervalSince1970 * 1000)
        return epochMs / timeBucketMs
    }

    // MARK: - Full Reward Calculation

    // Calculates the reward amount for completing a habit once.
    // Returns a rounded integer (like Math.round in JS).
    //
    // This combines all four multipliers:
    //   Reward = round(100 * G * D * F * R)
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
        // Int(reward.rounded()) matches JS Math.round — rounds half-up.
        return Int(reward.rounded())
    }

    // MARK: - Trade Helpers

    // Human-readable text describing which trade-required properties are missing.
    // Returns nil when both are set (i.e. the habit can trade).
    static func missingTradeProperties(frequency: Double?, difficultyRank: String?) -> String? {
        switch (frequency == nil, difficultyRank == nil) {
        case (true, true): return "frequency and difficulty"
        case (true, false): return "frequency"
        case (false, true): return "difficulty"
        case (false, false): return nil
        }
    }

    // MARK: - Time Bucket Helpers

    // Returns the number of nanoseconds until the next 30-minute time bucket
    // boundary. Used to sleep precisely until the price will change, rather
    // than polling on a fixed interval.
    static func nanosUntilNextBucket(now: Date = Date()) -> UInt64 {
        let epochMs = now.timeIntervalSince1970 * 1000
        let bucketMs = Double(timeBucketMs)
        let msIntoCurrentBucket = epochMs.truncatingRemainder(dividingBy: bucketMs)
        let msUntilNext = bucketMs - msIntoCurrentBucket
        // Convert ms → nanoseconds. Add a small buffer (100ms) to ensure we
        // land just after the boundary, not right on the edge due to floating
        // point imprecision.
        return UInt64((msUntilNext + 100) * 1_000_000)
    }

    // MARK: - Multi-Purchase Total

    // Calculates the total reward for completing a habit multiple times in one
    // trade. Each successive completion increments completionsInPeriod, which
    // changes the frequency multiplier F, so the total is NOT simply price * N.
    //
    // For example, completing a habit 3 times starting from 0 completions:
    //   total = price(completions=0) + price(completions=1) + price(completions=2)
    //
    // This matters because the frequency multiplier drops as completions increase
    // (diminishing returns), so the 3rd completion is worth less than the 1st.
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
