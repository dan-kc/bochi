import Foundation

enum DependencyActionSupport {
    @discardableResult
    static func completeTaskDependency(
        _ task: TaskItem,
        taskStore: TaskStore,
        taskDependencyStore: TaskDependencyStore,
        tradeStore: TradeStore,
        balanceStore: BalanceStore,
        hasPremiumAccess: Bool
    ) -> Bool {
        guard !taskDependencyStore.isTaskBlocked(task, taskStore: taskStore, tradeStore: tradeStore) else {
            return false
        }

        _ = TaskCompletionService.completeTask(
            taskID: task.id,
            sourceName: task.name,
            price: TaskPriceCalculator.calculatePrice(
                task: task,
                hasPremiumAccess: hasPremiumAccess
            ),
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore
        )
        return true
    }

    static func recurringTaskClaimRoute(
        for recurringTask: RecurringTask,
        tradeStore _: TradeStore
    ) -> RecurringTaskTradeRoute {
        RecurringTaskTradeRoute(
            recurringTask: recurringTask
        )
    }
}
