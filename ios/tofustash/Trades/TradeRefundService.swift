import Foundation

@MainActor
enum TradeRefundService {
    static func setRefunded(
        _ refunded: Bool,
        for trade: Trade,
        tradeStore: TradeStore,
        taskStore: TaskStore,
        balanceStore: BalanceStore,
        now: Date = Date()
    ) {
        if refunded {
            tradeStore.refundTrade(id: trade.id, refundedAt: now)
        } else {
            tradeStore.unrefundTrade(id: trade.id, updatedAt: now)
        }

        syncTaskCompletionIfNeeded(for: trade, tradeStore: tradeStore, taskStore: taskStore, updatedAt: now)
        balanceStore.refresh()
    }

    private static func syncTaskCompletionIfNeeded(
        for trade: Trade,
        tradeStore: TradeStore,
        taskStore: TaskStore,
        updatedAt: Date
    ) {
        guard let taskID = trade.taskId else { return }
        guard let task = taskStore.tasks.first(where: { $0.id == taskID && $0.deletedAt == nil }) else { return }

        let activeCompletionDate = tradeStore.activeTaskTradeCompletionDate(taskId: taskID)
        guard task.completedAt != activeCompletionDate else { return }

        taskStore.updateTask(
            id: taskID,
            completedAt: .some(activeCompletionDate),
            updatedAt: updatedAt
        )
    }
}
