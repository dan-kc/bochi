import Foundation

// Snapshot of the reward pricing inputs the user saw before opening the buy
// sheet. Dynamic cadence pricing depends on both history and "now", so the
// sheet and purchase service should spend against the same visible quote.
struct RewardPurchaseQuote: Equatable, Sendable {
    let purchaseDates: [Date]
    let pricedAt: Date

    nonisolated func totalPrice(
        reward: Reward,
        allRewards: [Reward],
        quantity: Int,
        fallbackNow _: Date = Date(),
        oneTimeAdjustmentMultiplier: Double? = nil,
        hasPremiumAccess: Bool = true
    ) -> Int {
        RewardPriceCalculator.calculateMultiPurchaseTotal(
            reward: reward,
            allRewards: allRewards,
            purchaseDates: purchaseDates,
            quantity: quantity,
            now: pricedAt,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    nonisolated func prices(
        reward: Reward,
        allRewards: [Reward],
        quantity: Int,
        fallbackNow _: Date = Date(),
        oneTimeAdjustmentMultiplier: Double? = nil,
        hasPremiumAccess: Bool = true
    ) -> [Int] {
        var projectedPurchaseDates = purchaseDates
        var prices: [Int] = []

        for _ in 0..<quantity {
            prices.append(
                RewardPriceCalculator.calculatePrice(
                    reward: reward,
                    allRewards: allRewards,
                    purchaseDates: projectedPurchaseDates,
                    now: pricedAt,
                    oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                    hasPremiumAccess: hasPremiumAccess
                )
            )
            projectedPurchaseDates.append(pricedAt)
        }

        return prices
    }
}
