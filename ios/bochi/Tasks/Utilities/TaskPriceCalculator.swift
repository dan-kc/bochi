import Foundation

// Pure functions for one-time task pricing.
enum TaskPriceCalculator {
    nonisolated static func calculatePrice(
        task: TaskItem,
        oneTimeAdjustmentMultiplier: Double? = nil,
        hasPremiumAccess: Bool = true
    ) -> Int {
        return PriceAdjustmentSupport.adjustedRoundedAmount(
            Double(task.basePrice),
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            hasPremiumAccess: hasPremiumAccess
        )
    }
}
