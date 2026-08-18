import Foundation

enum RewardPurchaseError: Error, Equatable {
    case insufficientBalance(required: Int, available: Int)
    case locked(secondsRemaining: Int)
    case dependenciesIncomplete
    case alreadyPurchased

    var message: String {
        switch self {
        case let .insufficientBalance(required, available):
            return "Need \(required) points but only have \(available)."
        case let .locked(secondsRemaining):
            return "This reward is locked for \(DurationFormatting.countdown(secondsRemaining: secondsRemaining))."
        case .dependenciesIncomplete:
            return "Complete this reward's dependencies before buying it."
        case .alreadyPurchased:
            return "This one-time reward has already been purchased."
        }
    }
}

// Small mutation coordinator for the "buy reward" workflow. Extracting this
// out of the SwiftUI sheet keeps the business rule testable at the store layer.
@MainActor
enum RewardPurchaseService {
    @discardableResult
    static func purchase(
        reward: Reward,
        rewardStore: RewardStore,
        rewardDependencyStore: RewardDependencyStore,
        taskStore: TaskStore,
        tradeStore: TradeStore,
        balanceStore: BalanceStore,
        oneTimeAdjustmentMultiplier: Double? = nil,
        oneTimeAdjustedTotal: Int? = nil,
        quote: RewardPurchaseQuote? = nil,
        quantity: Int = 1,
        hasPremiumAccess: Bool = true,
        allowsRestrictedPurchase: Bool = false
    ) throws -> Int {
        let purchaseDate = Date()
        if !allowsRestrictedPurchase {
            if let remainingSeconds = RewardLockout.remainingSeconds(
                reward: reward,
                tradeStore: tradeStore,
                now: purchaseDate,
                hasPremiumAccess: hasPremiumAccess
            ) {
                throw RewardPurchaseError.locked(secondsRemaining: remainingSeconds)
            }
            if rewardDependencyStore.isRewardBlocked(
                reward,
                taskStore: taskStore,
                tradeStore: tradeStore,
                hasPremiumAccess: hasPremiumAccess
            ) {
                throw RewardPurchaseError.dependenciesIncomplete
            }
        }
        if !reward.recurring && !tradeStore.rewardPurchaseDates(rewardId: reward.id).isEmpty {
            throw RewardPurchaseError.alreadyPurchased
        }

        let effectiveQuantity = reward.recurring
            ? (hasPremiumAccess && rewardDependencyStore.hasDependencies(for: reward.id) ? 1 : quantity)
            : 1
        let prices: [Int]
        let basePrices: [Int]

        if let quote {
            basePrices = quote.prices(
                reward: reward,
                allRewards: rewardStore.activeRewards,
                quantity: effectiveQuantity,
                oneTimeAdjustmentMultiplier: nil,
                hasPremiumAccess: false
            )
            if hasPremiumAccess, let oneTimeAdjustedTotal {
                prices = PriceAdjustmentSupport.distributedPrices(
                    adjustedTotal: oneTimeAdjustedTotal,
                    basePrices: basePrices
                )
            } else {
                prices = quote.prices(
                    reward: reward,
                    allRewards: rewardStore.activeRewards,
                    quantity: effectiveQuantity,
                    oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                    hasPremiumAccess: hasPremiumAccess
                )
            }
        } else {
            var purchaseDates = tradeStore.rewardPurchaseDates(rewardId: reward.id)
            var livePrices: [Int] = []
            var liveBasePrices: [Int] = []

            for _ in 0..<effectiveQuantity {
                let price = RewardPriceCalculator.calculatePrice(
                    reward: reward,
                    allRewards: rewardStore.activeRewards,
                    purchaseDates: purchaseDates,
                    now: purchaseDate,
                    oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                    hasPremiumAccess: hasPremiumAccess
                )
                let basePrice = RewardPriceCalculator.calculatePrice(
                    reward: reward,
                    allRewards: rewardStore.activeRewards,
                    purchaseDates: purchaseDates,
                    now: purchaseDate,
                    hasPremiumAccess: false
                )
                livePrices.append(price)
                liveBasePrices.append(basePrice)
                purchaseDates.append(purchaseDate)
            }

            basePrices = liveBasePrices
            if hasPremiumAccess, let oneTimeAdjustedTotal {
                prices = PriceAdjustmentSupport.distributedPrices(
                    adjustedTotal: oneTimeAdjustedTotal,
                    basePrices: basePrices
                )
            } else {
                prices = livePrices
            }
        }
        let totalPrice = prices.reduce(0, +)

        guard balanceStore.balance >= totalPrice else {
            throw RewardPurchaseError.insufficientBalance(required: totalPrice, available: balanceStore.balance)
        }

        let oneTimeSnapshot = oneTimeAdjustmentSnapshot(
            multiplier: oneTimeAdjustmentMultiplier,
            adjustedTotal: hasPremiumAccess ? oneTimeAdjustedTotal : nil,
            baseTotal: basePrices.reduce(0, +),
            actualTotal: totalPrice
        )
        let hasAdjustment = oneTimeSnapshot != nil
        let entries = zip(prices, basePrices).map { price, basePrice in
            // User behaviour: every purchase in a multi-buy keeps the exact
            // quoted cost that contributed to the visible total.
            (id: RecordID(), amount: -price, adjustmentBaseAmount: hasAdjustment ? -basePrice : nil)
        }

        tradeStore.addRewardPurchases(
            entries: entries,
            rewardId: reward.id,
            sourceName: reward.name,
            oneTimeAdjustmentMultiplier: oneTimeSnapshot,
            createdAt: purchaseDate
        )
        if hasPremiumAccess {
            rewardDependencyStore.resetRecurringTaskDependencies(for: reward.id, tradeStore: tradeStore)
        }
        balanceStore.refresh()
        return totalPrice
    }

    private static func oneTimeAdjustmentSnapshot(
        multiplier: Double?,
        adjustedTotal: Int?,
        baseTotal: Int,
        actualTotal: Int
    ) -> Double? {
        guard adjustedTotal != nil || multiplier != nil else { return nil }
        return multiplier
            ?? PriceAdjustmentSupport.multiplier(forAdjustedPrice: actualTotal, basePrice: baseTotal)
            ?? 1.0
    }
}
