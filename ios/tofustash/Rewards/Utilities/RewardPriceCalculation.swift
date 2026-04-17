import Foundation

// Pure pricing functions for rewards. This intentionally stays separate from
// Habit reward calculation because the frequency curve is inverted: buying a
// reward near or above its cap should get more expensive, not cheaper.
enum RewardPriceCalculation {
    nonisolated private static let beta = 3.0
    nonisolated private static let randomBaseMultiplier = 0.993
    nonisolated private static let randomMultiplierRange = 0.014
    nonisolated private static let maxFrequencyMultiplier = 50.0
    nonisolated private static let defaultPeriodDays = 60.0
    nonisolated private static let timeBucketMs = 30 * 60 * 1000

    nonisolated static func calculateDamageMultiplier(reward: Reward, allRewards: [Reward]) -> Double {
        let rankedRewards = allRewards
            .filter { $0.damageRank != nil && $0.deletedAt == nil }
            .sorted { $0.damageRank! < $1.damageRank! }

        guard !rankedRewards.isEmpty, reward.damageRank != nil else {
            return 0.5
        }

        guard let position = rankedRewards.firstIndex(where: { $0.id == reward.id }) else {
            return 0.5
        }

        let n = Double(rankedRewards.count)
        let rank = Double(position + 1)
        return (n - rank + 1) / (n + 1)
    }

    nonisolated static func calculateFrequencyMultiplier(
        reward: Reward,
        purchasesInPeriod: Int,
        periodDays: Double = defaultPeriodDays
    ) -> Double {
        guard let maxFrequency = reward.maxFrequency, maxFrequency != 0 else {
            return 1
        }

        let expectedPurchases = maxFrequency * periodDays
        guard expectedPurchases != 0 else {
            return 1
        }

        let effectiveRatio = Double(purchasesInPeriod) / expectedPurchases

        if effectiveRatio >= 1 {
            return maxFrequencyMultiplier
        }

        let multiplier = 2 / (1 - pow(effectiveRatio, beta)) - 1
        return min(multiplier, maxFrequencyMultiplier)
    }

    nonisolated static func calculateRandomMultiplier(rewardId: String, timeBucket: Int) -> Double {
        let hash = DeterministicHash.hash("\(rewardId)-\(timeBucket)")
        return randomBaseMultiplier + hash * randomMultiplierRange
    }

    nonisolated static func getCurrentTimeBucket(now: Date = Date()) -> Int {
        let epochMs = Int(now.timeIntervalSince1970 * 1000)
        return epochMs / timeBucketMs
    }

    nonisolated static func nanosUntilNextBucket(now: Date = Date()) -> UInt64 {
        let epochMs = now.timeIntervalSince1970 * 1000
        let bucketMs = Double(timeBucketMs)
        let msIntoCurrentBucket = epochMs.truncatingRemainder(dividingBy: bucketMs)
        let msUntilNext = bucketMs - msIntoCurrentBucket
        return UInt64((msUntilNext + 100) * 1_000_000)
    }

    nonisolated static func calculatePrice(
        reward: Reward,
        allRewards: [Reward],
        purchasesInPeriod: Int = 0,
        timeBucket: Int = getCurrentTimeBucket(),
        generalDifficulty: Double = 5.0
    ) -> Int {
        let damageMultiplier = calculateDamageMultiplier(reward: reward, allRewards: allRewards)
        let frequencyMultiplier = calculateFrequencyMultiplier(reward: reward, purchasesInPeriod: purchasesInPeriod)
        let randomMultiplier = calculateRandomMultiplier(rewardId: reward.id, timeBucket: timeBucket)

        let price = 100.0 * generalDifficulty * damageMultiplier * frequencyMultiplier * randomMultiplier
        return Int(price.rounded())
    }

    // Buying multiple rewards is summed one purchase at a time because the
    // max-frequency multiplier gets steeper after each purchase.
    nonisolated static func calculateMultiPurchaseTotal(
        reward: Reward,
        allRewards: [Reward],
        currentPurchases: Int,
        quantity: Int,
        timeBucket: Int = getCurrentTimeBucket(),
        generalDifficulty: Double = 5.0
    ) -> Int {
        var total = 0
        for index in 0..<quantity {
            total += calculatePrice(
                reward: reward,
                allRewards: allRewards,
                purchasesInPeriod: currentPurchases + index,
                timeBucket: timeBucket,
                generalDifficulty: generalDifficulty
            )
        }
        return total
    }
}
