import Foundation
import Testing
@testable import bochi

@MainActor
struct RewardPurchaseServiceTests {
    private func makeRewardStore(storageURL: URL) -> RewardStore {
        let store = RewardStore(storageURL: storageURL)
        _ = store.addReward(id: "reward-1", name: "Chocolate", maxFrequency: 1.0, basePrice: 200)
        return store
    }

    // Behaviour: Buying a reward creates a negative trade tied to that reward and reduces the visible balance.
    @Test("purchase records a reward trade and subtracts balance")
    func purchaseMutatesTradeHistoryAndBalance() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-purchase")
        let rewardStore = makeRewardStore(storageURL: storageURL)
        let rewardDependencyStore = RewardDependencyStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        tradeStore.addRecurringTaskTrade(recurringTaskId: "seed-recurringTask", amount: 2_000, shouldNotifySync: false)
        balanceStore.refresh()

        let reward = try #require(rewardStore.activeRewards.first)
        let spent = try RewardPurchaseService.purchase(
            reward: reward,
            rewardStore: rewardStore,
            rewardDependencyStore: rewardDependencyStore,
            taskStore: taskStore,
            tradeStore: tradeStore,
            balanceStore: balanceStore
        )

        #expect(spent > 0)
        let rewardTrades = tradeStore.trades.filter { $0.rewardId == reward.id }
        #expect(rewardTrades.count == 1)
        #expect(rewardTrades[0].recurringTaskId == nil)
        #expect(rewardTrades[0].amount == -spent)
        #expect(balanceStore.balance == 2_000 - spent)
    }

    // Behaviour: Buying multiple units in one go creates one trade per purchase
    // so future prices still reflect each individual buy.
    @Test("purchase with quantity records multiple reward trades")
    func purchaseQuantityCreatesMultipleTrades() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-purchase-quantity")
        let rewardStore = RewardStore(storageURL: storageURL)
        let rewardDependencyStore = RewardDependencyStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        _ = rewardStore.addReward(id: "reward-1", name: "Chocolate", maxFrequency: 3.0, basePrice: 200)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        tradeStore.addRecurringTaskTrade(recurringTaskId: "seed-recurringTask", amount: 10_000, shouldNotifySync: false)
        balanceStore.refresh()

        let reward = try #require(rewardStore.activeRewards.first)
        let spent = try RewardPurchaseService.purchase(
            reward: reward,
            rewardStore: rewardStore,
            rewardDependencyStore: rewardDependencyStore,
            taskStore: taskStore,
            tradeStore: tradeStore,
            balanceStore: balanceStore,
            quantity: 3
        )

        #expect(spent > 0)
        #expect(tradeStore.rewardPurchaseDates(rewardId: reward.id).count == 3)
        #expect(tradeStore.trades.filter { $0.rewardId == reward.id }.count == 3)
        #expect(balanceStore.balance == 10_000 - spent)
    }

    // Behaviour: a typed one-time adjusted total should be the exact amount
    // spent, even when a multi-purchase creates separate trade rows.
    @Test("purchase with a typed adjustment records the exact multi-purchase total")
    func purchaseQuantityWithTypedAdjustmentUsesExactTotal() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-purchase-typed-adjustment")
        let rewardStore = RewardStore(storageURL: storageURL)
        let rewardDependencyStore = RewardDependencyStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        _ = rewardStore.addReward(id: "reward-1", name: "Chocolate", maxFrequency: 3.0, basePrice: 200)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        tradeStore.addRecurringTaskTrade(recurringTaskId: "seed-recurringTask", amount: 10_000, shouldNotifySync: false)
        balanceStore.refresh()

        let reward = try #require(rewardStore.activeRewards.first)
        let spent = try RewardPurchaseService.purchase(
            reward: reward,
            rewardStore: rewardStore,
            rewardDependencyStore: rewardDependencyStore,
            taskStore: taskStore,
            tradeStore: tradeStore,
            balanceStore: balanceStore,
            oneTimeAdjustedTotal: 501,
            quantity: 3
        )

        let rewardTrades = tradeStore.trades.filter { $0.rewardId == reward.id }
        #expect(spent == 501)
        #expect(rewardTrades.count == 3)
        #expect(rewardTrades.map(\.amount).reduce(0, +) == -501)
        #expect(rewardTrades.allSatisfy { $0.adjustmentBaseAmount != nil })
        #expect(rewardTrades.allSatisfy { $0.oneTimeAdjustmentMultiplier != nil })
        #expect(balanceStore.balance == 9_499)
    }

    // Behaviour: Trying to buy a reward without enough points leaves both balance and history unchanged.
    @Test("purchase blocks when balance is insufficient")
    func purchaseBlocksOnLowBalance() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-low-balance")
        let rewardStore = makeRewardStore(storageURL: storageURL)
        let rewardDependencyStore = RewardDependencyStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        let reward = try #require(rewardStore.activeRewards.first)

        do {
            _ = try RewardPurchaseService.purchase(
                reward: reward,
                rewardStore: rewardStore,
                rewardDependencyStore: rewardDependencyStore,
                taskStore: taskStore,
                tradeStore: tradeStore,
                balanceStore: balanceStore
            )
            Issue.record("Expected insufficient balance error")
        } catch let error as RewardPurchaseError {
            switch error {
            case let .insufficientBalance(required, available):
                #expect(required > 0)
                #expect(available == 0)
            case .locked:
                Issue.record("Expected insufficient balance error instead of reward lockout")
            case .dependenciesIncomplete:
                Issue.record("Expected insufficient balance error instead of dependency lockout")
            case .alreadyPurchased:
                Issue.record("Expected insufficient balance error instead of one-time purchase lockout")
            }
        }

        #expect(tradeStore.trades.isEmpty)
        #expect(balanceStore.balance == 0)
    }

    // Behaviour: Reward lockout should block new purchases until the cooldown
    // expires, even when the user can afford the reward.
    @Test("purchase blocks while the reward is locked")
    func purchaseBlocksWhileRewardIsLocked() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-locked-purchase")
        let rewardStore = RewardStore(storageURL: storageURL)
        let rewardDependencyStore = RewardDependencyStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        _ = rewardStore.addReward(
            id: "reward-1",
            name: "Chocolate",
            maxFrequency: 1.0,
            lockoutDurationSeconds: 3_600,
            basePrice: 200
        )
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        tradeStore.addRecurringTaskTrade(recurringTaskId: "seed-recurringTask", amount: 2_000, shouldNotifySync: false)
        tradeStore.addRewardPurchase(
            rewardId: "reward-1",
            amount: -100,
            createdAt: Date().addingTimeInterval(-300),
            shouldNotifySync: false
        )
        balanceStore.refresh()

        let reward = try #require(rewardStore.activeRewards.first)

        do {
            _ = try RewardPurchaseService.purchase(
                reward: reward,
                rewardStore: rewardStore,
                rewardDependencyStore: rewardDependencyStore,
                taskStore: taskStore,
                tradeStore: tradeStore,
                balanceStore: balanceStore
            )
            Issue.record("Expected reward lockout error")
        } catch let error as RewardPurchaseError {
            switch error {
            case .insufficientBalance:
                Issue.record("Expected reward lockout error instead of insufficient balance")
            case .locked:
                break
            case .dependenciesIncomplete:
                Issue.record("Expected reward lockout error instead of dependency lockout")
            case .alreadyPurchased:
                Issue.record("Expected reward lockout error instead of one-time purchase lockout")
            }
        }

        #expect(tradeStore.trades.filter { $0.rewardId == reward.id }.count == 1)
    }

    // Behaviour: after the user confirms the small warning modal, the purchase
    // service should allow a locked recurring reward to be bought anyway.
    @Test("confirmed purchase can bypass reward lockout")
    func confirmedPurchaseCanBypassRewardLockout() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-confirmed-locked-purchase")
        let rewardStore = RewardStore(storageURL: storageURL)
        let rewardDependencyStore = RewardDependencyStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        _ = rewardStore.addReward(
            id: "reward-1",
            name: "Chocolate",
            maxFrequency: 3.0,
            lockoutDurationSeconds: 3_600,
            basePrice: 200
        )
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        tradeStore.addRecurringTaskTrade(recurringTaskId: "seed-recurringTask", amount: 10_000, shouldNotifySync: false)
        tradeStore.addRewardPurchase(
            rewardId: "reward-1",
            amount: -100,
            createdAt: Date().addingTimeInterval(-300),
            shouldNotifySync: false
        )
        balanceStore.refresh()

        let reward = try #require(rewardStore.activeRewards.first)

        _ = try RewardPurchaseService.purchase(
            reward: reward,
            rewardStore: rewardStore,
            rewardDependencyStore: rewardDependencyStore,
            taskStore: taskStore,
            tradeStore: tradeStore,
            balanceStore: balanceStore,
            allowsRestrictedPurchase: true
        )

        #expect(tradeStore.rewardPurchaseDates(rewardId: reward.id).count == 2)
    }

    // Behaviour: if premium lapses, a saved reward lockout should stop
    // blocking purchases while still preserving the purchase history.
    @Test("lapsed premium purchase ignores saved reward lockout")
    func lapsedPremiumPurchaseIgnoresSavedRewardLockout() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-lapsed-lockout-purchase")
        let rewardStore = RewardStore(storageURL: storageURL)
        let rewardDependencyStore = RewardDependencyStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        _ = rewardStore.addReward(
            id: "reward-1",
            name: "Chocolate",
            maxFrequency: 3.0,
            lockoutDurationSeconds: 3_600,
            basePrice: 200
        )
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        tradeStore.addRecurringTaskTrade(recurringTaskId: "seed-recurringTask", amount: 10_000, shouldNotifySync: false)
        tradeStore.addRewardPurchase(
            rewardId: "reward-1",
            amount: -100,
            createdAt: Date().addingTimeInterval(-300),
            shouldNotifySync: false
        )
        balanceStore.refresh()

        let reward = try #require(rewardStore.activeRewards.first)

        _ = try RewardPurchaseService.purchase(
            reward: reward,
            rewardStore: rewardStore,
            rewardDependencyStore: rewardDependencyStore,
            taskStore: taskStore,
            tradeStore: tradeStore,
            balanceStore: balanceStore,
            hasPremiumAccess: false
        )

        #expect(tradeStore.rewardPurchaseDates(rewardId: reward.id).count == 2)
    }

    // Behaviour: buying a dependency-gated reward consumes the recurringTask progress
    // by resetting the baseline to the current completion count.
    @Test("purchase resets completed recurringTask dependency progress")
    func purchaseResetsRecurringTaskDependencyProgress() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-dependency-reset")
        let rewardStore = RewardStore(storageURL: storageURL)
        let rewardDependencyStore = RewardDependencyStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        _ = rewardStore.addReward(id: "reward-1", name: "Chocolate", maxFrequency: 3.0, basePrice: 200)
        tradeStore.addRecurringTaskTrade(recurringTaskId: "seed-recurringTask", amount: 10_000, shouldNotifySync: false)
        tradeStore.addRecurringTaskTrade(recurringTaskId: "recurringTask-1", amount: 100, shouldNotifySync: false)
        tradeStore.addRecurringTaskTrade(recurringTaskId: "recurringTask-1", amount: 100, shouldNotifySync: false)
        balanceStore.refresh()

        let reward = try #require(rewardStore.activeRewards.first)
        rewardDependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [],
            recurringTaskDependencies: [
                RewardRecurringTaskDependency(
                    rewardId: reward.id,
                    recurringTaskId: "recurringTask-1",
                    requiredCompletions: 2,
                    baselineCompletionCount: 0,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil
                )
            ],
            shouldNotifySync: false
        )

        _ = try RewardPurchaseService.purchase(
            reward: reward,
            rewardStore: rewardStore,
            rewardDependencyStore: rewardDependencyStore,
            taskStore: taskStore,
            tradeStore: tradeStore,
            balanceStore: balanceStore,
            quantity: 3
        )

        let dependency = try #require(rewardDependencyStore.activeRecurringTaskDependencies(for: reward.id).first)
        #expect(dependency.baselineCompletionCount == 2)
        #expect(rewardDependencyStore.recurringTaskDependencyProgress(for: dependency, tradeStore: tradeStore) == 0)
        #expect(tradeStore.rewardPurchaseDates(rewardId: reward.id).count == 1)
    }
}
