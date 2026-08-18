import Foundation

struct RewardListRowModel: Identifiable, Sendable {
    let reward: Reward
    let tags: [Tag]
    let price: Int
    let isLocked: Bool
    let isBlocked: Bool
    let isSpent: Bool
    let canRefund: Bool
    let canAfford: Bool
    let quote: RewardPurchaseQuote

    nonisolated var id: RecordID { reward.id }
}

struct RewardListProjection: Sendable {
    var activeRewards: [Reward] = []
    var visibleRewardRows: [RewardListRowModel] = []

    var rowIDs: [RecordID] {
        visibleRewardRows.map(\.id)
    }
}

struct RewardListProjectionInputs: Sendable {
    let rewards: [Reward]
    let tasks: [TaskItem]
    let rewardTagsByID: [RecordID: [Tag]]
    let activeTagIDs: Set<RecordID>
    let rewardTaskDependencies: [RewardTaskDependency]
    let rewardRecurringTaskDependencies: [RewardRecurringTaskDependency]
    let latestTaskTradesByTaskID: [RecordID: Trade]
    let recurringTaskCompletionCountsByRecurringTaskID: [RecordID: Int]
    let rewardPurchaseDatesByRewardID: [RecordID: [Date]]
    let latestRewardPurchasesByRewardID: [RecordID: Trade]
    let balance: Int
    let preferences: EntityListPreferences
    let hasPremiumAccess: Bool
    let now: Date
}

nonisolated enum SpendListProjectionBuilder {
    static func makeProjection(inputs: RewardListProjectionInputs) -> RewardListProjection {
        let activeRewards = inputs.rewards.filter { $0.deletedAt == nil }
        let rewardRows = rewardRows(rewards: activeRewards, inputs: inputs)
        let visibleRewardRows = orderedRewardRows(rows: visibleRewardRows(rewardRows, inputs: inputs))

        return RewardListProjection(
            activeRewards: activeRewards,
            visibleRewardRows: visibleRewardRows
        )
    }

    private static func rewardRows(
        rewards: [Reward],
        inputs: RewardListProjectionInputs
    ) -> [RewardListRowModel] {
        let blockedRewardIDs = EntityDependencyBlockingSupport.blockedRewardIDs(
            rewards: rewards,
            allTasks: inputs.tasks,
            rewardTaskDependencies: inputs.rewardTaskDependencies,
            rewardRecurringTaskDependencies: inputs.rewardRecurringTaskDependencies,
            latestTaskTradesByTaskID: inputs.latestTaskTradesByTaskID,
            recurringTaskCompletionCountsByRecurringTaskID: inputs.recurringTaskCompletionCountsByRecurringTaskID,
            hasPremiumAccess: inputs.hasPremiumAccess
        )

        return rewards.map { reward in
            let purchaseDates = inputs.rewardPurchaseDatesByRewardID[reward.id, default: []]
            let isLocked = RewardLockout.remainingSeconds(
                reward: reward,
                purchaseDates: purchaseDates,
                now: inputs.now,
                hasPremiumAccess: inputs.hasPremiumAccess
            ) != nil
            let quote = RewardPurchaseQuote(
                purchaseDates: purchaseDates,
                pricedAt: inputs.now
            )
            let price = quote.totalPrice(
                reward: reward,
                allRewards: rewards,
                quantity: 1
            )
            let isBlocked = blockedRewardIDs.contains(reward.id)
            let canPurchaseNow = reward.canPurchase && !isLocked && !isBlocked
            let latestPurchase = inputs.latestRewardPurchasesByRewardID[reward.id]
            let isSpent = !reward.recurring && latestPurchase != nil

            return RewardListRowModel(
                reward: reward,
                tags: inputs.rewardTagsByID[reward.id, default: []],
                price: price,
                isLocked: isLocked,
                isBlocked: isBlocked,
                isSpent: isSpent,
                canRefund: latestPurchase != nil,
                canAfford: canPurchaseNow && !isSpent && inputs.balance >= price,
                quote: quote
            )
        }
    }

    private static func visibleRewardRows(
        _ rows: [RewardListRowModel],
        inputs: RewardListProjectionInputs
    ) -> [RewardListRowModel] {
        EntityListQuery.apply(
            items: rows,
            preferences: inputs.preferences,
            hasPremiumAccess: inputs.hasPremiumAccess,
            validTagIDs: inputs.activeTagIDs,
            id: \.id,
            createdAt: \.reward.createdAt,
            price: { row in
                EntityActionSupport.sortableAmount(isActionable: row.reward.canPurchase && !row.isLocked && !row.isBlocked) {
                    row.price
                }
            },
            tags: \.tags,
            statuses: \.statuses,
            isPinned: \.reward.pinned
        )
    }

    private static func orderedRewardRows(
        rows: [RewardListRowModel]
    ) -> [RewardListRowModel] {
        [
            (isLocked: false, isHidden: false),
            (isLocked: true, isHidden: false),
            (isLocked: false, isHidden: true),
            (isLocked: true, isHidden: true)
        ].flatMap { group in
            rows.filter { row in
                row.isUnavailable == group.isLocked
                    && row.reward.hidden == group.isHidden
            }
        }
    }
}

extension RewardListRowModel {
    nonisolated var isUnavailable: Bool {
        isLocked || isBlocked || isSpent
    }

    nonisolated var statuses: Set<EntityListStatusFilter> {
        var statuses: Set<EntityListStatusFilter> = []
        if reward.recurring {
            statuses.insert(.recurringTask)
        }
        if reward.hidden {
            statuses.insert(.hidden)
        }
        if isUnavailable {
            statuses.insert(.locked)
        }
        return statuses
    }

    nonisolated var listStatus: EntityListRowStatus? {
        if isLocked || isBlocked {
            return .locked
        }
        if reward.hidden {
            return .hidden
        }
        if isSpent {
            return .completed
        }
        return nil
    }
}
