import Foundation

struct TaskCompletionPriceSnapshot: Equatable, Sendable {
    let price: Int
    let adjustmentBaseAmount: Int?
    let oneTimeAdjustmentMultiplier: Double?
}

enum TaskCompletionService {
    nonisolated static func priceSnapshot(
        task: TaskItem,
        oneTimeAdjustmentMultiplier: Double? = nil,
        oneTimeAdjustedPrice: Int? = nil,
        hasPremiumAccess: Bool = true
    ) -> TaskCompletionPriceSnapshot {
        let basePrice = TaskPriceCalculator.calculatePrice(
            task: task
        )
        let adjustedPriceOverride = hasPremiumAccess ? oneTimeAdjustedPrice : nil
        let hasAdjustment = adjustedPriceOverride != nil || (hasPremiumAccess && oneTimeAdjustmentMultiplier != nil)
        let oneTimeSnapshot = hasAdjustment
            ? (oneTimeAdjustmentMultiplier ?? PriceAdjustmentSupport.multiplier(
                forAdjustedPrice: adjustedPriceOverride ?? basePrice,
                basePrice: basePrice
            ) ?? 1.0)
            : nil
        let price = adjustedPriceOverride ?? TaskPriceCalculator.calculatePrice(
            task: task,
            oneTimeAdjustmentMultiplier: oneTimeSnapshot,
            hasPremiumAccess: hasPremiumAccess
        )
        let baseAmount = hasAdjustment ? basePrice : nil

        return TaskCompletionPriceSnapshot(
            price: price,
            adjustmentBaseAmount: baseAmount,
            oneTimeAdjustmentMultiplier: oneTimeSnapshot
        )
    }

    @MainActor
    static func completeTask(
        taskID: RecordID,
        sourceName: String? = nil,
        price: Int,
        adjustmentBaseAmount: Int? = nil,
        oneTimeAdjustmentMultiplier: Double? = nil,
        tradeStore: TradeStore,
        taskStore: TaskStore,
        balanceStore: BalanceStore,
        claimDate: Date = Date()
    ) -> Date? {
        guard
            let task = taskStore.tasks.first(where: { $0.id == taskID }),
            task.deletedAt == nil,
            tradeStore.latestTaskTrade(taskId: taskID, includeRefunded: false) == nil
        else {
            return nil
        }

        tradeStore.addTaskTrade(
            taskId: taskID,
            sourceName: sourceName,
            amount: price,
            adjustmentBaseAmount: adjustmentBaseAmount,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            createdAt: claimDate
        )
        balanceStore.refresh()
        return claimDate
    }
}
