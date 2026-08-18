import Foundation
import Testing
@testable import bochi

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
        balanceStore.refresh()
        #expect(balanceStore.balance == 120)

        let initialTrade = try #require(tradeStore.trades.first(where: { $0.id == "trade-1" }))
        let refundTrade = try #require(
            TradeRefundService.refund(
            for: initialTrade,
            tradeStore: tradeStore,
            balanceStore: balanceStore,
            now: refundedAt
            )
        )

        #expect(tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false) == nil)
        #expect(refundTrade.refundsTradeId == initialTrade.id)
        #expect(refundTrade.amount == -120)
        #expect(balanceStore.balance == 0)

        let secondCompletion = TaskCompletionService.completeTask(
            taskID: task.id,
            sourceName: task.name,
            price: 120,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore,
            claimDate: secondCompletionAt
        )
        #expect(secondCompletion == secondCompletionAt)
        #expect(tradeStore.trades.count == 3)
        #expect(balanceStore.balance == 120)

        #expect(tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false)?.createdAt == secondCompletionAt)
    }

    // Behaviour: completing a task should create exactly one earning trade
    // that the frontend uses as the completion source and refresh balance.
    @Test("task completion records one trade and refreshes balance")
    func taskCompletionRecordsTradeAndRefreshesBalance() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        let claimDate = Date(timeIntervalSince1970: 1_800_001_000)

        let task = try #require(taskStore.addTask(id: "task-complete", name: "Submit report", shouldNotifySync: false))

        let completedAt = TaskCompletionService.completeTask(
            taskID: task.id,
            sourceName: task.name,
            price: 75,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore,
            claimDate: claimDate
        )

        #expect(completedAt == claimDate)
        #expect(balanceStore.balance == 75)
        let trade = try #require(tradeStore.trades.first)
        #expect(trade.taskId == task.id)
        #expect(trade.sourceName == "Submit report")
        #expect(trade.amount == 75)
        #expect(trade.createdAt == claimDate)
        #expect(tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false)?.createdAt == claimDate)
    }

    // Behaviour: trying to complete a task that is already complete should not
    // create a duplicate earning trade or change the balance.
    @Test("task completion refuses already completed tasks")
    func taskCompletionRefusesAlreadyCompletedTasks() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        let firstDate = Date(timeIntervalSince1970: 1_800_001_100)
        let secondDate = firstDate.addingTimeInterval(60)

        let task = try #require(taskStore.addTask(id: "task-complete-once", name: "Submit report", shouldNotifySync: false))
        _ = TaskCompletionService.completeTask(
            taskID: task.id,
            sourceName: task.name,
            price: 75,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore,
            claimDate: firstDate
        )

        let secondCompletion = TaskCompletionService.completeTask(
            taskID: task.id,
            sourceName: task.name,
            price: 75,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore,
            claimDate: secondDate
        )

        #expect(secondCompletion == nil)
        #expect(tradeStore.trades.count == 1)
        #expect(balanceStore.balance == 75)
        #expect(tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false)?.createdAt == firstDate)
    }

    // Behaviour: a task with an existing active completion trade should not
    // award points again.
    @Test("task completion refuses an active existing task trade")
    func taskCompletionRefusesExistingActiveTrade() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)

        let task = try #require(taskStore.addTask(id: "task-active-trade", name: "Submit report", shouldNotifySync: false))
        tradeStore.addTaskTrade(
            id: "trade-existing",
            taskId: task.id,
            sourceName: task.name,
            amount: 75,
            createdAt: Date(timeIntervalSince1970: 1_800_001_200),
            shouldNotifySync: false
        )
        balanceStore.refresh()

        let completedAt = TaskCompletionService.completeTask(
            taskID: task.id,
            sourceName: task.name,
            price: 75,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore,
            claimDate: Date(timeIntervalSince1970: 1_800_001_300)
        )

        #expect(completedAt == nil)
        #expect(tradeStore.trades.count == 1)
        #expect(balanceStore.balance == 75)
        #expect(tradeStore.latestTaskTrade(taskId: task.id, includeRefunded: false)?.id == "trade-existing")
    }

    // Behaviour: deleted tasks are no longer actionable and should never award
    // points from stale UI or delayed callbacks.
    @Test("task completion refuses deleted tasks")
    func taskCompletionRefusesDeletedTasks() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)

        let task = try #require(taskStore.addTask(id: "task-deleted", name: "Submit report", shouldNotifySync: false))
        taskStore.deleteTask(id: task.id, deletedAt: Date(timeIntervalSince1970: 1_800_001_400), shouldNotifySync: false)

        let completedAt = TaskCompletionService.completeTask(
            taskID: task.id,
            sourceName: task.name,
            price: 75,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore,
            claimDate: Date(timeIntervalSince1970: 1_800_001_500)
        )

        #expect(completedAt == nil)
        #expect(tradeStore.trades.isEmpty)
        #expect(balanceStore.balance == 0)
    }
}
