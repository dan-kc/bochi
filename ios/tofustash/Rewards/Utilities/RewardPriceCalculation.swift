import Foundation

// Pure pricing functions for rewards. This intentionally stays separate from
// Habit reward calculation because the frequency curve is inverted: buying a
// reward near or above its cap should get more expensive, not cheaper.
enum RewardPriceCalculation {
    nonisolated private static let beta = 3.0
    nonisolated private static let maxFrequencyMultiplier = 50.0

    // Rewards price against a rolling 24-hour window so caps like "3/day"
    // react on the same day the user exceeds them.
    nonisolated static let pricingWindowDays = 1

    nonisolated static func calculateDamageMultiplier(reward: Reward, allRewards: [Reward]) -> Double {
        reward.damageTier?.multiplier ?? RewardDamageTier.medium.multiplier
    }

    nonisolated static func calculateFrequencyMultiplier(
        reward: Reward,
        purchasesInPeriod: Int,
        periodDays: Double = Double(pricingWindowDays)
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

    nonisolated static func calculatePrice(
        reward: Reward,
        allRewards: [Reward],
        purchasesInPeriod: Int = 0,
        generalDifficulty: Double = 5.0
    ) -> Int {
        let damageMultiplier = calculateDamageMultiplier(reward: reward, allRewards: allRewards)
        let frequencyMultiplier = calculateFrequencyMultiplier(reward: reward, purchasesInPeriod: purchasesInPeriod)

        let price = 100.0 * generalDifficulty * damageMultiplier * frequencyMultiplier
        return Int(price.rounded())
    }

    nonisolated static func calculateMultiPurchaseTotal(
        reward: Reward,
        allRewards: [Reward],
        currentPurchases: Int,
        quantity: Int,
        generalDifficulty: Double = 5.0
    ) -> Int {
        var total = 0
        for index in 0..<quantity {
            total += calculatePrice(
                reward: reward,
                allRewards: allRewards,
                purchasesInPeriod: currentPurchases + index,
                generalDifficulty: generalDifficulty
            )
        }
        return total
    }
}
