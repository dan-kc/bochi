import Foundation
import Testing
@testable import bochi

@MainActor
struct TaskCompletionServiceTests {
    private func makeStorageURL() -> URL {
        TestHelpers.makeTemporaryFileURL("task-completion-support")
    }

    // Behaviour: task completion from the claim modal should record the
    // adjusted amount and the base price snapshot used by trade history.
    @Test("task completion with a premium one-time adjustment stores its price snapshot")
    func adjustedCompletionStoresPriceSnapshot() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        let task = try #require(
            taskStore.addTask(
                name: "Submit report",
                basePrice: 200,
                shouldNotifySync: false
            )
        )
        let claimDate = Date(timeIntervalSince1970: 1_800_000_000)

        let snapshot = TaskCompletionService.priceSnapshot(
            task: task,
            oneTimeAdjustmentMultiplier: 1.5,
            hasPremiumAccess: true
        )
        let completedAt = TaskCompletionService.completeTask(
            taskID: task.id,
            sourceName: task.name,
            price: snapshot.price,
            adjustmentBaseAmount: snapshot.adjustmentBaseAmount,
            oneTimeAdjustmentMultiplier: snapshot.oneTimeAdjustmentMultiplier,
            tradeStore: tradeStore,
            taskStore: taskStore,
            balanceStore: balanceStore,
            claimDate: claimDate
        )

        let trade = try #require(tradeStore.trades.first)
        #expect(completedAt == claimDate)
        #expect(snapshot.price == 300)
        #expect(snapshot.adjustmentBaseAmount == 200)
        #expect(trade.amount == snapshot.price)
        #expect(trade.adjustmentBaseAmount == 200)
        #expect(trade.oneTimeAdjustmentMultiplier == 1.5)
        #expect(balanceStore.balance == snapshot.price)
    }

    // Behaviour: when the claim sheet lets the user type a new price, the task
    // completion uses that exact amount rather than exposing multiplier math.
    @Test("task completion with a typed one-time adjustment uses the exact price")
    func typedAdjustedCompletionUsesExactPrice() {
        let task = TaskItem(
            id: "task-1",
            name: "Submit report",
            description: "",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            deletedAt: nil,
            basePrice: 200,
            dueDate: nil
        )

        let snapshot = TaskCompletionService.priceSnapshot(
            task: task,
            oneTimeAdjustedPrice: 333,
            hasPremiumAccess: true
        )

        #expect(snapshot.price == 333)
        #expect(snapshot.adjustmentBaseAmount == 200)
        #expect(snapshot.oneTimeAdjustmentMultiplier == 333.0 / 200.0)
    }

    // Behaviour: premium-only one-time adjustments should not leak into task
    // completion snapshots after premium lapses.
    @Test("task completion snapshot ignores one-time adjustments without premium")
    func lapsedPremiumSnapshotDoesNotStoreAdjustments() {
        let task = TaskItem(
            id: "task-1",
            name: "Submit report",
            description: "",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            deletedAt: nil,
            basePrice: 200,
            dueDate: nil
        )

        let snapshot = TaskCompletionService.priceSnapshot(
            task: task,
            oneTimeAdjustmentMultiplier: 0.5,
            hasPremiumAccess: false
        )

        #expect(snapshot.price == 200)
        #expect(snapshot.adjustmentBaseAmount == nil)
        #expect(snapshot.oneTimeAdjustmentMultiplier == nil)
    }
}
