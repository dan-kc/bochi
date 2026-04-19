import Foundation

// Pure pricing functions for rewards. This intentionally stays separate from
// Habit reward calculation because the frequency curve is inverted: buying a
// reward near or above its cap should get more expensive, not cheaper.
enum RewardPriceCalculation {
    nonisolated private static let beta = 3.0
    nonisolated private static let maxFrequencyMultiplier = 50.0
    nonisolated private static let rewardNeutralRatio = 0.0

    nonisolated static func calculateDamageMultiplier(reward: Reward, allRewards: [Reward]) -> Double {
        reward.damageTier?.multiplier ?? RewardDamageTier.medium.multiplier
    }

    nonisolated static func calculateFrequencyMultiplier(
        reward: Reward,
        purchaseDates: [Date],
        now: Date = Date()
    ) -> Double {
        guard let targetSpacingDays = CadenceDecayPricing.targetSpacingDays(ratePerDay: reward.maxFrequency) else {
            return 1
        }

        let rawRatio = CadenceDecayPricing.normalizedUsageRatio(
            eventDates: purchaseDates,
            targetSpacingDays: targetSpacingDays,
            now: now
        )
        let effectiveRatio = CadenceDecayPricing.blendedUsageRatio(
            rawRatio: rawRatio,
            createdAt: reward.createdAt,
            targetSpacingDays: targetSpacingDays,
            neutralRatio: rewardNeutralRatio,
            now: now
        )

        if effectiveRatio >= 1 {
            return maxFrequencyMultiplier
        }

        let multiplier = 2 / (1 - pow(effectiveRatio, beta)) - 1
        return min(multiplier, maxFrequencyMultiplier)
    }

    nonisolated static func calculatePrice(
        reward: Reward,
        allRewards: [Reward],
        purchaseDates: [Date] = [],
        now: Date = Date(),
        generalDifficulty: Double = 5.0
    ) -> Int {
        let damageMultiplier = calculateDamageMultiplier(reward: reward, allRewards: allRewards)
        let frequencyMultiplier = calculateFrequencyMultiplier(
            reward: reward,
            purchaseDates: purchaseDates,
            now: now
        )

        let price = 100.0 * generalDifficulty * damageMultiplier * frequencyMultiplier
        return Int(price.rounded())
    }

    nonisolated static func calculateMultiPurchaseTotal(
        reward: Reward,
        allRewards: [Reward],
        purchaseDates: [Date],
        quantity: Int,
        now: Date = Date(),
        generalDifficulty: Double = 5.0
    ) -> Int {
        var total = 0
        var projectedPurchaseDates = purchaseDates

        for _ in 0..<quantity {
            total += calculatePrice(
                reward: reward,
                allRewards: allRewards,
                purchaseDates: projectedPurchaseDates,
                now: now,
                generalDifficulty: generalDifficulty
            )
            projectedPurchaseDates.append(now)
        }
        return total
    }
}
