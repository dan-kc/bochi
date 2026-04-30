import Foundation

enum TaskCompletionSupport {
    @MainActor
    static func completeTask(
        taskID: RecordID,
        sourceName: String? = nil,
        reward: Int,
        tradeStore: TradeStore,
        taskStore: TaskStore,
        balanceStore: BalanceStore,
        claimDate: Date = Date()
    ) -> Date? {
        guard
            let task = taskStore.tasks.first(where: { $0.id == taskID }),
            task.deletedAt == nil,
            task.completedAt == nil,
            tradeStore.latestTaskTrade(taskId: taskID, includeRefunded: true) == nil
        else {
            return nil
        }

        tradeStore.addTaskTrade(taskId: taskID, sourceName: sourceName, amount: reward, createdAt: claimDate)
        taskStore.completeTask(id: taskID, completedAt: claimDate)
        balanceStore.refresh()
        return claimDate
    }
}
