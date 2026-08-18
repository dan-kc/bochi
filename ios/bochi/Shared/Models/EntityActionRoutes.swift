import Foundation

struct RecurringTaskTradeRoute: Identifiable {
    let recurringTask: RecurringTask
    let quote: RecurringTaskTradeQuote?
    let allowsRestrictedClaim: Bool

    init(
        recurringTask: RecurringTask,
        quote: RecurringTaskTradeQuote? = nil,
        allowsRestrictedClaim: Bool = false
    ) {
        self.recurringTask = recurringTask
        self.quote = quote
        self.allowsRestrictedClaim = allowsRestrictedClaim
    }

    var id: RecordID { recurringTask.id }
}

struct RewardPurchaseRoute: Identifiable {
    let reward: Reward
    let quote: RewardPurchaseQuote?
    let allowsRestrictedPurchase: Bool

    init(
        reward: Reward,
        quote: RewardPurchaseQuote? = nil,
        allowsRestrictedPurchase: Bool = false
    ) {
        self.reward = reward
        self.quote = quote
        self.allowsRestrictedPurchase = allowsRestrictedPurchase
    }

    var id: RecordID { reward.id }
}
