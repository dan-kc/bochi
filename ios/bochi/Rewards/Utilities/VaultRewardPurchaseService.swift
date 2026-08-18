import Foundation

enum VaultRewardPurchaseError: Error, Equatable {
    case insufficientVaultBalance(required: Int, available: Int)
    case vaultLocked(secondsRemaining: Int)
    case rewardLocked
    case dependenciesIncomplete
    case alreadyPurchased

    var message: String {
        switch self {
        case let .insufficientVaultBalance(required, available):
            return "Need \(required) bank points but only have \(available)."
        case let .vaultLocked(secondsRemaining):
            return "Bank purchases are available in \(DurationFormatting.countdown(secondsRemaining: secondsRemaining))."
        case .rewardLocked:
            return "This reward is locked right now."
        case .dependenciesIncomplete:
            return "Complete this reward's dependencies before buying it."
        case .alreadyPurchased:
            return "This one-time reward has already been purchased."
        }
    }
}

@MainActor
enum VaultRewardPurchaseService {
    static let cooldownSeconds = 30 * 24 * 60 * 60

    static func remainingVaultCooldown(tradeStore: TradeStore, now: Date = Date()) -> Int? {
        guard let availableAt = tradeStore.nextVaultPurchaseAvailableAt(now: now) else { return nil }
        return max(0, Int(ceil(availableAt.timeIntervalSince(now))))
    }

    @discardableResult
    static func purchase(
        reward: Reward,
        rewardStore: RewardStore,
        rewardDependencyStore: RewardDependencyStore,
        taskStore: TaskStore,
        tradeStore: TradeStore,
        oneTimeAdjustmentMultiplier: Double? = nil,
        oneTimeAdjustedTotal: Int? = nil,
        quote: RewardPurchaseQuote? = nil,
        quantity: Int = 1,
        hasPremiumAccess: Bool = true,
        now: Date = Date()
    ) throws -> Int {
        if let remaining = remainingVaultCooldown(tradeStore: tradeStore, now: now) {
            throw VaultRewardPurchaseError.vaultLocked(secondsRemaining: remaining)
        }
        if RewardLockout.isLocked(
            reward: reward,
            tradeStore: tradeStore,
            now: now,
            hasPremiumAccess: hasPremiumAccess
        ) {
            throw VaultRewardPurchaseError.rewardLocked
        }
        if rewardDependencyStore.isRewardBlocked(
            reward,
            taskStore: taskStore,
            tradeStore: tradeStore,
            hasPremiumAccess: hasPremiumAccess
        ) {
            throw VaultRewardPurchaseError.dependenciesIncomplete
        }
        if !reward.recurring && !tradeStore.rewardPurchaseDates(rewardId: reward.id).isEmpty {
            throw VaultRewardPurchaseError.alreadyPurchased
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
            let price = RewardPriceCalculator.calculatePrice(
                reward: reward,
                allRewards: rewardStore.activeRewards,
                purchaseDates: tradeStore.rewardPurchaseDates(rewardId: reward.id),
                now: now,
                oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                hasPremiumAccess: hasPremiumAccess
            )
            let basePrice = RewardPriceCalculator.calculatePrice(
                reward: reward,
                allRewards: rewardStore.activeRewards,
                purchaseDates: tradeStore.rewardPurchaseDates(rewardId: reward.id),
                now: now,
                hasPremiumAccess: false
            )
            basePrices = Array(repeating: basePrice, count: effectiveQuantity)
            if hasPremiumAccess, let oneTimeAdjustedTotal {
                prices = PriceAdjustmentSupport.distributedPrices(
                    adjustedTotal: oneTimeAdjustedTotal,
                    basePrices: basePrices
                )
            } else {
                prices = Array(repeating: price, count: effectiveQuantity)
            }
        }

        let totalPrice = prices.reduce(0, +)
        let requiredVaultBalance = VaultAmount.microUnits(forWholeBochi: totalPrice)
        let vaultBalance = tradeStore.vaultBalanceMicro()
        guard vaultBalance >= requiredVaultBalance else {
            throw VaultRewardPurchaseError.insufficientVaultBalance(
                required: totalPrice,
                available: VaultAmount.wholeBochi(fromMicroUnits: vaultBalance)
            )
        }

        let oneTimeSnapshot = oneTimeAdjustmentSnapshot(
            multiplier: oneTimeAdjustmentMultiplier,
            adjustedTotal: hasPremiumAccess ? oneTimeAdjustedTotal : nil,
            baseTotal: basePrices.reduce(0, +),
            actualTotal: totalPrice
        )
        let hasAdjustment = oneTimeSnapshot != nil
        let entries = zip(prices, basePrices).map { price, basePrice in
            (id: RecordID(), amount: -price, adjustmentBaseAmount: hasAdjustment ? -basePrice : nil)
        }

        tradeStore.addVaultRewardPurchases(
            entries: entries,
            rewardId: reward.id,
            sourceName: reward.name,
            oneTimeAdjustmentMultiplier: oneTimeSnapshot,
            createdAt: now
        )
        if hasPremiumAccess {
            rewardDependencyStore.resetRecurringTaskDependencies(for: reward.id, tradeStore: tradeStore)
        }
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
