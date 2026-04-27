import Foundation
import Testing
@testable import tofustash

@MainActor
struct RewardPurchaseServiceTests {
    private func makeRewardStore(storageURL: URL) -> RewardStore {
        let store = RewardStore(storageURL: storageURL)
        _ = store.addReward(id: "reward-1", name: "Chocolate", maxFrequency: 1.0, damageTier: .medium)
        return store
    }

    // Behaviour: Buying a reward creates a negative trade tied to that reward and reduces the visible balance.
    @Test("purchase records a reward trade and subtracts balance")
    func purchaseMutatesTradeHistoryAndBalance() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-purchase")
        let rewardStore = makeRewardStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        tradeStore.addHabitTrade(habitId: "seed-habit", amount: 2_000, shouldNotifySync: false)
        balanceStore.refresh()

        let reward = try #require(rewardStore.activeRewards.first)
        let spent = try RewardPurchaseService.purchase(
            reward: reward,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            balanceStore: balanceStore,
            generalDifficulty: 5,
        )

        #expect(spent > 0)
        let rewardTrades = tradeStore.trades.filter { $0.rewardId == reward.id }
        #expect(rewardTrades.count == 1)
        #expect(rewardTrades[0].habitId == nil)
        #expect(rewardTrades[0].amount == -spent)
        #expect(balanceStore.balance == 2_000 - spent)
    }

    // Behaviour: Buying multiple units in one go creates one trade per purchase
    // so future prices still reflect each individual buy.
    @Test("purchase with quantity records multiple reward trades")
    func purchaseQuantityCreatesMultipleTrades() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-purchase-quantity")
        let rewardStore = RewardStore(storageURL: storageURL)
        _ = rewardStore.addReward(id: "reward-1", name: "Chocolate", maxFrequency: 3.0, damageTier: .medium)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        tradeStore.addHabitTrade(habitId: "seed-habit", amount: 10_000, shouldNotifySync: false)
        balanceStore.refresh()

        let reward = try #require(rewardStore.activeRewards.first)
        let spent = try RewardPurchaseService.purchase(
            reward: reward,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            balanceStore: balanceStore,
            generalDifficulty: 5,
            quantity: 3
        )

        #expect(spent > 0)
        #expect(tradeStore.rewardPurchaseDates(rewardId: reward.id).count == 3)
        #expect(tradeStore.trades.filter { $0.rewardId == reward.id }.count == 3)
        #expect(balanceStore.balance == 10_000 - spent)
    }

    // Behaviour: Trying to buy a reward without enough tofu leaves both balance and history unchanged.
    @Test("purchase blocks when balance is insufficient")
    func purchaseBlocksOnLowBalance() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-low-balance")
        let rewardStore = makeRewardStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        let reward = try #require(rewardStore.activeRewards.first)

        do {
            _ = try RewardPurchaseService.purchase(
                reward: reward,
                rewardStore: rewardStore,
                tradeStore: tradeStore,
                balanceStore: balanceStore,
                generalDifficulty: 5
            )
            Issue.record("Expected insufficient balance error")
        } catch let error as RewardPurchaseError {
            switch error {
            case let .insufficientBalance(required, available):
                #expect(required > 0)
                #expect(available == 0)
            }
        }

        #expect(tradeStore.trades.isEmpty)
        #expect(balanceStore.balance == 0)
    }
}
