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
            reopenTaskIfNeeded(for: trade, taskStore: taskStore, updatedAt: now)
        } else {
            tradeStore.unrefundTrade(id: trade.id, updatedAt: now)
            restoreTaskCompletionIfNeeded(for: trade, taskStore: taskStore, updatedAt: now)
        }

        balanceStore.refresh()
    }

    private static func reopenTaskIfNeeded(
        for trade: Trade,
        taskStore: TaskStore,
        updatedAt: Date
    ) {
        guard let taskID = trade.taskId else { return }
        guard taskStore.tasks.contains(where: { $0.id == taskID && $0.deletedAt == nil }) else { return }

        taskStore.updateTask(
            id: taskID,
            completedAt: .some(nil),
            updatedAt: updatedAt
        )
    }

    private static func restoreTaskCompletionIfNeeded(
        for trade: Trade,
        taskStore: TaskStore,
        updatedAt: Date
    ) {
        guard let taskID = trade.taskId else { return }
        guard taskStore.tasks.contains(where: { $0.id == taskID && $0.deletedAt == nil }) else { return }

        taskStore.updateTask(
            id: taskID,
            completedAt: .some(Optional(trade.createdAt)),
            updatedAt: updatedAt
        )
    }
}
