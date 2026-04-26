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
        let purchaseDate = Date()
        var purchaseDates = tradeStore.rewardPurchaseDates(rewardId: reward.id)
        let totalPrice = RewardPriceCalculation.calculateMultiPurchaseTotal(
            reward: reward,
            allRewards: rewardStore.activeRewards,
            purchaseDates: purchaseDates,
            quantity: quantity,
            now: purchaseDate,
            generalDifficulty: generalDifficulty
        )

        guard balanceStore.balance >= totalPrice else {
            throw RewardPurchaseError.insufficientBalance(required: totalPrice, available: balanceStore.balance)
        }

        var entries: [(id: RecordID, amount: Int)] = []
        for _ in 0..<quantity {
            let price = RewardPriceCalculation.calculatePrice(
                reward: reward,
                allRewards: rewardStore.activeRewards,
                purchaseDates: purchaseDates,
                now: purchaseDate,
                generalDifficulty: generalDifficulty
            )
            entries.append((id: RecordID(), amount: -price))
            purchaseDates.append(purchaseDate)
        }

        tradeStore.addRewardPurchases(entries: entries, rewardId: reward.id, createdAt: purchaseDate)
        balanceStore.refresh()
        return totalPrice
    }
}
