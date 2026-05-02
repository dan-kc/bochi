import Foundation

@MainActor
enum TradeRefundService {
    @discardableResult
    static func refund(
        for trade: Trade,
        tradeStore: TradeStore,
        taskStore: TaskStore,
        balanceStore: BalanceStore,
        now: Date = Date()
    ) -> Trade? {
        let refundTrade = tradeStore.refundTrade(id: trade.id, refundedAt: now)
        guard let refundTrade else { return nil }

        syncTaskCompletionIfNeeded(for: trade, tradeStore: tradeStore, taskStore: taskStore, updatedAt: now)
        balanceStore.refresh()
        return refundTrade
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
