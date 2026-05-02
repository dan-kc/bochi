import Foundation
import Testing
@testable import tofustash

@MainActor
struct TradeRefundServiceTests {

    private func makeStorageURL() -> URL {
        TestHelpers.makeTemporaryFileURL("trade-refund-service")
    }

    // Behaviour: refunding a task completion should reopen the task and allow
    // the user to complete it again as a fresh trade later.
    @Test("task trade refunds reopen the task and allow a fresh completion")
    func taskTradeRefundReopensTaskAndAllowsFreshCompletion() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let refundedAt = completedAt.addingTimeInterval(300)
        let secondCompletionAt = refundedAt.addingTimeInterval(60)

        let task = try #require(taskStore.addTask(id: "task-1", name: "Submit report", shouldNotifySync: false))
        tradeStore.addTaskTrade(id: "trade-1", taskId: task.id, sourceName: task.name, amount: 120, createdAt: completedAt, shouldNotifySync: false)
        taskStore.completeTask(id: task.id, completedAt: completedAt, shouldNotifySync: false)
        balanceStore.refresh()
        #expect(balanceStore.balance == 120)

        let initialTrade = try #require(tradeStore.trades.first(where: { $0.id == "trade-1" }))
        let refundTrade = try #require(
            TradeRefundService.refund(
            for: initialTrade,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore,
            now: refundedAt
            )
        )

        let refundedTask = try #require(taskStore.tasks.first(where: { $0.id == task.id }))
        #expect(refundedTask.completedAt == nil)
        #expect(refundTrade.refundsTradeId == initialTrade.id)
        #expect(refundTrade.amount == -120)
        #expect(balanceStore.balance == 0)

        let secondCompletion = TaskCompletionSupport.completeTask(
            taskID: task.id,
            sourceName: task.name,
            reward: 120,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore,
            claimDate: secondCompletionAt
        )
        #expect(secondCompletion == secondCompletionAt)
        #expect(tradeStore.trades.count == 3)
        #expect(balanceStore.balance == 120)

        let completedTask = try #require(taskStore.tasks.first(where: { $0.id == task.id }))
        #expect(completedTask.completedAt == secondCompletionAt)
    }
}
