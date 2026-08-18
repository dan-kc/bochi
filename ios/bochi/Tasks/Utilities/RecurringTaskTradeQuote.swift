import Foundation

// Snapshot of the recurringTask pricing inputs the user saw before opening the claim
// sheet. Dynamic cadence pricing depends on both history and "now", so the
// sheet should keep using this quote until the claim finishes or is cancelled.
struct RecurringTaskTradeQuote: Equatable, Sendable {
    let completionDates: [Date]
    let pricedAt: Date

    nonisolated func totalPrice(
        recurringTask: RecurringTask,
        allRecurringTasks: [RecurringTask],
        quantity: Int,
        fallbackNow _: Date = Date(),
        oneTimeAdjustmentMultiplier: Double? = nil,
        hasPremiumAccess: Bool = true
    ) -> Int {
        RecurringTaskPriceCalculator.calculateMultiClaimTotal(
            recurringTask: recurringTask,
            allRecurringTasks: allRecurringTasks,
            completionDates: completionDates,
            quantity: quantity,
            now: pricedAt,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    nonisolated func prices(
        recurringTask: RecurringTask,
        allRecurringTasks: [RecurringTask],
        quantity: Int,
        fallbackNow _: Date = Date(),
        oneTimeAdjustmentMultiplier: Double? = nil,
        hasPremiumAccess: Bool = true
    ) -> [Int] {
        var projectedCompletionDates = completionDates
        var prices: [Int] = []

        for _ in 0..<quantity {
            prices.append(
                RecurringTaskPriceCalculator.calculatePrice(
                    recurringTask: recurringTask,
                    allRecurringTasks: allRecurringTasks,
                    completionDates: projectedCompletionDates,
                    now: pricedAt,
                    oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                    hasPremiumAccess: hasPremiumAccess
                )
            )
            projectedCompletionDates.append(pricedAt)
        }

        return prices
    }
}
