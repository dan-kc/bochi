import Foundation

// Pure functions for calculating the points amount a user sees when completing a
// recurringTask.
//
// Formula: Price = round(basePrice * F)
//   F = frequency multiplier based on completion rate, range (0, 2)
enum RecurringTaskPriceCalculator {

    // Higher values make prices react more strongly when the user drifts away
    // from the target cadence for this recurringTask.
    nonisolated private static let alpha = 3.75

    // New recurringTasks warm up toward "on target" instead of immediately assuming
    // the user is under-performing a brand-new recurringTask with no real history yet.
    nonisolated private static let recurringTaskNeutralRatio = 1.0
    nonisolated private static let activityWarmupCompletionsMultiplier = 30.0
    nonisolated private static let maxActivityWarmupWeight = 0.25

    nonisolated static func calculateFrequencyMultiplier(
        recurringTask: RecurringTask,
        completionDates: [Date],
        now: Date = Date()
    ) -> Double {
        let configuredRate = recurringTask.frequency ?? FrequencyBounds.maximumDailyRate
        guard let targetSpacingDays = CadenceDecayPricing.targetSpacingDays(ratePerDay: configuredRate) else {
            return 1.0
        }

        let rawRatio = CadenceDecayPricing.normalizedUsageRatio(
            eventDates: completionDates,
            targetSpacingDays: targetSpacingDays,
            now: now
        )
        let effectiveRatio = recurringTaskEffectiveUsageRatio(
            rawRatio: rawRatio,
            createdAt: recurringTask.createdAt,
            targetSpacingDays: targetSpacingDays,
            configuredRate: configuredRate,
            completionCount: completionDates.count,
            now: now
        )

        return 2.0 / (1.0 + pow(effectiveRatio, alpha))
    }

    nonisolated private static func recurringTaskEffectiveUsageRatio(
        rawRatio: Double,
        createdAt: Date,
        targetSpacingDays: Double,
        configuredRate: Double,
        completionCount: Int,
        now: Date
    ) -> Double {
        let ageBlendedRatio = CadenceDecayPricing.blendedUsageRatio(
            rawRatio: rawRatio,
            createdAt: createdAt,
            targetSpacingDays: targetSpacingDays,
            neutralRatio: recurringTaskNeutralRatio,
            now: now
        )
        guard rawRatio > recurringTaskNeutralRatio else {
            return ageBlendedRatio
        }

        // User behaviour: if someone immediately repeats a new recurringTask several
        // times, we should begin trusting that overuse signal even before the
        // age-based warm-up period has elapsed.
        let activityWeight = min(
            maxActivityWarmupWeight,
            Double(completionCount) / (configuredRate * activityWarmupCompletionsMultiplier)
        )
        let activityBlendedRatio = (activityWeight * rawRatio) + ((1.0 - activityWeight) * recurringTaskNeutralRatio)

        return max(ageBlendedRatio, activityBlendedRatio)
    }

    nonisolated static func calculatePrice(
        recurringTask: RecurringTask,
        allRecurringTasks: [RecurringTask],
        completionDates: [Date] = [],
        now: Date = Date(),
        oneTimeAdjustmentMultiplier: Double? = nil,
        hasPremiumAccess: Bool = true
    ) -> Int {
        let frequencyMultiplier = calculateFrequencyMultiplier(
            recurringTask: recurringTask,
            completionDates: completionDates,
            now: now
        )

        let price = Double(recurringTask.basePrice) * frequencyMultiplier
        return PriceAdjustmentSupport.adjustedRoundedAmount(
            price,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    nonisolated static func calculateMultiClaimTotal(
        recurringTask: RecurringTask,
        allRecurringTasks: [RecurringTask],
        completionDates: [Date],
        quantity: Int,
        now: Date = Date(),
        oneTimeAdjustmentMultiplier: Double? = nil,
        hasPremiumAccess: Bool = true
    ) -> Int {
        var total = 0
        var projectedCompletionDates = completionDates

        for _ in 0..<quantity {
            total += calculatePrice(
                recurringTask: recurringTask,
                allRecurringTasks: allRecurringTasks,
                completionDates: projectedCompletionDates,
                now: now,
                oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                hasPremiumAccess: hasPremiumAccess
            )
            projectedCompletionDates.append(now)
        }
        return total
    }
}
