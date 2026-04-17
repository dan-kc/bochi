import Testing
@testable import tofustash

@MainActor
struct RewardPurchaseServiceTests {
    private func makeRewardStore() -> RewardStore {
        let store = RewardStore()
        _ = store.addReward(id: "reward-1", name: "Chocolate", maxFrequency: 1.0, damageRank: "m")
        return store
    }

    // Behaviour: Buying a reward creates a negative trade tied to that reward and reduces the visible balance.
    @Test("purchase records a reward trade and subtracts balance")
    func purchaseMutatesTradeHistoryAndBalance() throws {
        let rewardStore = makeRewardStore()
        let tradeStore = TradeStore()
        let balanceStore = BalanceStore()
        balanceStore.addTofu(2_000)

        let reward = try #require(rewardStore.activeRewards.first)
        let spent = try RewardPurchaseService.purchase(
            reward: reward,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            balanceStore: balanceStore,
            generalDifficulty: 5,
            timeBucket: 12345
        )

        #expect(spent > 0)
        #expect(tradeStore.trades.count == 1)
        #expect(tradeStore.trades[0].rewardId == reward.id)
        #expect(tradeStore.trades[0].habitId == nil)
        #expect(tradeStore.trades[0].amount == -spent)
        #expect(balanceStore.balance == 2_000 - spent)
    }

    // Behaviour: Buying multiple units in one go creates one trade per purchase
    // so future prices still reflect each individual buy.
    @Test("purchase with quantity records multiple reward trades")
    func purchaseQuantityCreatesMultipleTrades() throws {
        let rewardStore = makeRewardStore()
        let tradeStore = TradeStore()
        let balanceStore = BalanceStore()
        balanceStore.addTofu(10_000)

        let reward = try #require(rewardStore.activeRewards.first)
        let spent = try RewardPurchaseService.purchase(
            reward: reward,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            balanceStore: balanceStore,
            generalDifficulty: 5,
            quantity: 3,
            timeBucket: 12345
        )

        #expect(spent > 0)
        #expect(tradeStore.trades.count == 3)
        #expect(tradeStore.trades.allSatisfy { $0.rewardId == reward.id })
        #expect(balanceStore.balance == 10_000 - spent)
    }

    // Behaviour: Trying to buy a reward without enough tofu leaves both balance and history unchanged.
    @Test("purchase blocks when balance is insufficient")
    func purchaseBlocksOnLowBalance() throws {
        let rewardStore = makeRewardStore()
        let tradeStore = TradeStore()
        let balanceStore = BalanceStore()
        let reward = try #require(rewardStore.activeRewards.first)

        do {
            _ = try RewardPurchaseService.purchase(
                reward: reward,
                rewardStore: rewardStore,
                tradeStore: tradeStore,
                balanceStore: balanceStore,
                generalDifficulty: 5,
                timeBucket: 12345
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
