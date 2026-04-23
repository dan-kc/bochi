import Foundation

// Pure pricing functions for rewards. This intentionally stays separate from
// Habit reward calculation because the frequency curve is inverted: buying a
// reward near or above its cap should get more expensive, not cheaper.
enum RewardPriceCalculation {
    // Lowering beta softens the ramp for high-frequency rewards so short
    // bursts do not explode into the cap as quickly, while sustained overuse
    // still gets expensive.
    nonisolated private static let beta = 2.5
    // Hard-cap the top-end so extreme or blank rewards stay expensive without
    // blowing out into prices that are unrealistic for the in-app economy.
    nonisolated private static let maxFrequencyMultiplier = 20.0
    nonisolated private static let rewardNeutralRatio = 0.0

    nonisolated static func calculateDamageMultiplier(reward: Reward, allRewards: [Reward]) -> Double {
        reward.damageTier?.multiplier ?? RewardDamageTier.extreme.multiplier
    }

    nonisolated static func calculateFrequencyMultiplier(
        reward: Reward,
        purchaseDates: [Date],
        now: Date = Date()
    ) -> Double {
        let configuredRate = reward.maxFrequency ?? FrequencyBounds.minimumDailyRate
        guard let targetSpacingDays = CadenceDecayPricing.targetSpacingDays(ratePerDay: configuredRate) else {
            return maxFrequencyMultiplier
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
        // Higher daily caps should allow a small same-day cluster before the
        // user hits the steepest part of the overuse curve.
        let adjustedRatio = effectiveRatio / burstAllowance(ratePerDay: configuredRate)

        if adjustedRatio >= 1 {
            return maxFrequencyMultiplier
        }

        let multiplier = 2 / (1 - pow(adjustedRatio, beta)) - 1
        return min(multiplier, maxFrequencyMultiplier)
    }

    nonisolated private static func burstAllowance(ratePerDay: Double) -> Double {
        max(1.0, sqrt(ratePerDay))
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
