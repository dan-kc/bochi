import Foundation

enum RewardPurchaseError: Error, Equatable {
    case insufficientBalance(required: Int, available: Int)

    var message: String {
        switch self {
        case let .insufficientBalance(required, available):
            return "Need \(required) tofu but only have \(available)."
        }
    }
}

// Small mutation coordinator for the "buy reward" workflow. Extracting this
// out of the SwiftUI sheet keeps the business rule testable without UI tests.
@MainActor
enum RewardPurchaseService {
    @discardableResult
    static func purchase(
        reward: Reward,
        rewardStore: RewardStore,
        tradeStore: TradeStore,
        balanceStore: BalanceStore,
        generalDifficulty: Double,
        quantity: Int = 1
    ) throws -> Int {
        let purchasesInPeriod = tradeStore.rewardPurchasesInPeriod(
            rewardId: reward.id,
            days: RewardPriceCalculation.pricingWindowDays
        )
        let totalPrice = RewardPriceCalculation.calculateMultiPurchaseTotal(
            reward: reward,
            allRewards: rewardStore.activeRewards,
            currentPurchases: purchasesInPeriod,
            quantity: quantity,
            generalDifficulty: generalDifficulty
        )

        guard balanceStore.balance >= totalPrice else {
            throw RewardPurchaseError.insufficientBalance(required: totalPrice, available: balanceStore.balance)
        }

        for index in 0..<quantity {
            let price = RewardPriceCalculation.calculatePrice(
                reward: reward,
                allRewards: rewardStore.activeRewards,
                purchasesInPeriod: purchasesInPeriod + index,
                generalDifficulty: generalDifficulty
            )
            tradeStore.addRewardPurchase(rewardId: reward.id, amount: -price)
        }

        balanceStore.subtractTofu(totalPrice)
        return totalPrice
    }
}
