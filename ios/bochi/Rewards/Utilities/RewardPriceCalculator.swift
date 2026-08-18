import Foundation

// Pure pricing functions for rewards. This intentionally stays separate from
// RecurringTask reward calculation because the frequency curve is inverted: buying a
// reward near or above its cap should get more expensive, not cheaper.
enum RewardPriceCalculator {
    // Lowering beta softens the ramp for high-frequency rewards so short
    // bursts do not explode into the cap as quickly, while sustained overuse
    // still gets expensive.
    nonisolated private static let beta = 2.5
    // Hard-cap the top-end so extreme or blank rewards stay expensive without
    // blowing out into prices that are unrealistic for the in-app economy.
    nonisolated private static let maxFrequencyMultiplier = 20.0
    // Once usage gets close to the cap, switch away from the asymptotic curve
    // so a brief over-cap burst is stern without jumping straight to the max.
    nonisolated private static let softCapKneeRatio = 0.85
    nonisolated private static let softOverCapRatio = 1.5
    nonisolated private static let softOverCapMultiplier = 5.5
    nonisolated private static let hardOverCapRamp = 6.0
    nonisolated private static let rewardNeutralRatio = 0.0

    nonisolated static func calculateFrequencyMultiplier(
        reward: Reward,
        purchaseDates: [Date],
        now: Date = Date()
    ) -> Double {
        guard reward.recurring else { return 1.0 }

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

        return frequencyMultiplier(forAdjustedRatio: adjustedRatio)
    }

    nonisolated private static func frequencyMultiplier(forAdjustedRatio adjustedRatio: Double) -> Double {
        let kneeMultiplier = asymptoticMultiplier(forRatio: softCapKneeRatio)

        if adjustedRatio <= softCapKneeRatio {
            return min(asymptoticMultiplier(forRatio: adjustedRatio), maxFrequencyMultiplier)
        }

        if adjustedRatio <= softOverCapRatio {
            let progress = (adjustedRatio - softCapKneeRatio) / (softOverCapRatio - softCapKneeRatio)
            let multiplier = kneeMultiplier + (progress * (softOverCapMultiplier - kneeMultiplier))
            return min(multiplier, maxFrequencyMultiplier)
        }

        let overage = adjustedRatio - softOverCapRatio
        let multiplier = softOverCapMultiplier + (hardOverCapRamp * pow(overage, 2))
        return min(multiplier, maxFrequencyMultiplier)
    }

    nonisolated private static func asymptoticMultiplier(forRatio ratio: Double) -> Double {
        2 / (1 - pow(ratio, beta)) - 1
    }

    nonisolated private static func burstAllowance(ratePerDay: Double) -> Double {
        max(1.0, sqrt(ratePerDay))
    }

    nonisolated static func calculatePrice(
        reward: Reward,
        allRewards: [Reward],
        purchaseDates: [Date] = [],
        now: Date = Date(),
        oneTimeAdjustmentMultiplier: Double? = nil,
        hasPremiumAccess: Bool = true
    ) -> Int {
        let frequencyMultiplier = calculateFrequencyMultiplier(
            reward: reward,
            purchaseDates: purchaseDates,
            now: now
        )

        let price = Double(reward.basePrice) * frequencyMultiplier
        return PriceAdjustmentSupport.adjustedRoundedAmount(
            price,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    nonisolated static func calculateMultiPurchaseTotal(
        reward: Reward,
        allRewards: [Reward],
        purchaseDates: [Date],
        quantity: Int,
        now: Date = Date(),
        oneTimeAdjustmentMultiplier: Double? = nil,
        hasPremiumAccess: Bool = true
    ) -> Int {
        var total = 0
        var projectedPurchaseDates = purchaseDates

        for _ in 0..<quantity {
            total += calculatePrice(
                reward: reward,
                allRewards: allRewards,
                purchaseDates: projectedPurchaseDates,
                now: now,
                oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                hasPremiumAccess: hasPremiumAccess
            )
            projectedPurchaseDates.append(now)
        }
        return total
    }
}
