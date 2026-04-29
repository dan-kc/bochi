import Foundation

enum TaskCompletionSupport {
    @MainActor
    static func completeTask(
        taskID: RecordID,
        reward: Int,
        tradeStore: TradeStore,
        taskStore: TaskStore,
        balanceStore: BalanceStore,
        claimDate: Date = Date()
    ) -> Date {
        tradeStore.addTaskTrade(taskId: taskID, amount: reward, createdAt: claimDate)
        taskStore.completeTask(id: taskID, completedAt: claimDate)
        balanceStore.refresh()
        return claimDate
    }
}
