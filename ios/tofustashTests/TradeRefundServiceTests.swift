import Foundation
import Testing
@testable import tofustash

@MainActor
struct TradeRefundServiceTests {

    private func makeStorageURL() -> URL {
        TestHelpers.makeTemporaryFileURL("trade-refund-service")
    }

    // Behaviour: refunding a task completion should reopen the task and remove
    // its tofu, while undoing the refund should restore both.
    @Test("task trade refunds reopen the task and can be undone without creating a second completion")
    func taskTradeRefundReopensTaskAndCanBeUndone() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let refundedAt = completedAt.addingTimeInterval(300)
        let attemptedSecondCompletionAt = refundedAt.addingTimeInterval(60)
        let unrefundedAt = refundedAt.addingTimeInterval(300)

        let task = try #require(taskStore.addTask(id: "task-1", name: "Submit report", shouldNotifySync: false))
        tradeStore.addTaskTrade(id: "trade-1", taskId: task.id, sourceName: task.name, amount: 120, createdAt: completedAt, shouldNotifySync: false)
        taskStore.completeTask(id: task.id, completedAt: completedAt, shouldNotifySync: false)
        balanceStore.refresh()
        #expect(balanceStore.balance == 120)

        let initialTrade = try #require(tradeStore.trades.first(where: { $0.id == "trade-1" }))
        TradeRefundService.setRefunded(
            true,
            for: initialTrade,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore,
            now: refundedAt
        )

        let refundedTask = try #require(taskStore.tasks.first(where: { $0.id == task.id }))
        let refundedTrade = try #require(tradeStore.trades.first(where: { $0.id == initialTrade.id }))
        #expect(refundedTask.completedAt == nil)
        #expect(refundedTrade.refundedAt == refundedAt)
        #expect(balanceStore.balance == 0)

        let attemptedSecondCompletion = TaskCompletionSupport.completeTask(
            taskID: task.id,
            sourceName: task.name,
            reward: 120,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore,
            claimDate: attemptedSecondCompletionAt
        )
        #expect(attemptedSecondCompletion == nil)
        #expect(tradeStore.trades.count == 1)
        #expect(balanceStore.balance == 0)

        let tradeToRestore = try #require(tradeStore.trades.first(where: { $0.id == initialTrade.id }))
        TradeRefundService.setRefunded(
            false,
            for: tradeToRestore,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore,
            now: unrefundedAt
        )

        let restoredTask = try #require(taskStore.tasks.first(where: { $0.id == task.id }))
        let restoredTrade = try #require(tradeStore.trades.first(where: { $0.id == initialTrade.id }))
        #expect(restoredTask.completedAt == completedAt)
        #expect(restoredTrade.refundedAt == nil)
        #expect(balanceStore.balance == 120)
    }
}
