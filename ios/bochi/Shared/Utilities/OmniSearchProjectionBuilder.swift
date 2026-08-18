import Foundation

struct OmniSearchTaskRowModel: Sendable {
    let task: TaskItem
    let tags: [Tag]
    let price: Int
    let canComplete: Bool
    let isCompleted: Bool
    let isBlocked: Bool
}

struct OmniSearchRecurringTaskRowModel: Sendable {
    let recurringTask: RecurringTask
    let tags: [Tag]
    let isLocked: Bool
    let price: Int
    let quote: RecurringTaskTradeQuote
}

struct OmniSearchRewardRowModel: Sendable {
    let reward: Reward
    let tags: [Tag]
    let price: Int
    let isLocked: Bool
    let isBlocked: Bool
    let isSpent: Bool
    let canRefund: Bool
    let quote: RewardPurchaseQuote
}

enum OmniSearchRowModel: Identifiable, Sendable {
    case task(OmniSearchTaskRowModel)
    case recurringTask(OmniSearchRecurringTaskRowModel)
    case reward(OmniSearchRewardRowModel)

    var id: OmniSearchResultID {
        switch self {
        case .task(let row):
            .task(row.task.id)
        case .recurringTask(let row):
            .recurringTask(row.recurringTask.id)
        case .reward(let row):
            .reward(row.reward.id)
        }
    }

    var role: BochiThemeRole {
        switch self {
        case .task:
            .task
        case .recurringTask:
            .recurringTask
        case .reward:
            .reward
        }
    }
}

struct OmniSearchProjection: Sendable {
    let queryText: String
    let preferences: EntityListPreferences
    let snapshot: OmniSearchSnapshot
    let rowsByID: [OmniSearchResultID: OmniSearchRowModel]

    var rows: [OmniSearchRowModel] {
        snapshot.results.compactMap { rowsByID[$0.id] }
    }

    var rowIDs: [OmniSearchResultID] {
        rows.map(\.id)
    }
}

struct OmniSearchProjectionInputs: Sendable {
    let queryText: String
    let preferences: EntityListPreferences
    let tasks: [TaskItem]
    let recurringTasks: [RecurringTask]
    let rewards: [Reward]
    let taskTagsByID: [RecordID: [Tag]]
    let recurringTaskTagsByID: [RecordID: [Tag]]
    let rewardTagsByID: [RecordID: [Tag]]
    let taskTaskDependencies: [TaskTaskDependency]
    let taskRecurringTaskDependencies: [TaskRecurringTaskDependency]
    let rewardTaskDependencies: [RewardTaskDependency]
    let rewardRecurringTaskDependencies: [RewardRecurringTaskDependency]
    let latestTaskTradesByTaskID: [RecordID: Trade]
    let recurringTaskCompletionCountsByRecurringTaskID: [RecordID: Int]
    let recurringTaskTradeDatesByRecurringTaskID: [RecordID: [Date]]
    let rewardPurchaseDatesByRewardID: [RecordID: [Date]]
    let latestRewardPurchasesByRewardID: [RecordID: Trade]
    let hasPremiumAccess: Bool
    let now: Date
}

nonisolated enum OmniSearchProjectionBuilder {
    static func makeProjection(inputs: OmniSearchProjectionInputs) -> OmniSearchProjection {
        let taskRows = makeTaskRows(inputs: inputs)
        let recurringTaskRows = makeRecurringTaskRows(inputs: inputs)
        let rewardRows = makeRewardRows(inputs: inputs)
        let rowsByID = makeRowsByID(
            taskRows: taskRows,
            recurringTaskRows: recurringTaskRows,
            rewardRows: rewardRows
        )

        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: taskRows.map(\.task),
            recurringTasks: recurringTaskRows.map(\.recurringTask),
            rewards: rewardRows.map(\.reward),
            queryText: inputs.queryText,
            taskTagsByID: Dictionary(uniqueKeysWithValues: taskRows.map { ($0.task.id, $0.tags) }),
            recurringTaskTagsByID: Dictionary(uniqueKeysWithValues: recurringTaskRows.map { ($0.recurringTask.id, $0.tags) }),
            rewardTagsByID: Dictionary(uniqueKeysWithValues: rewardRows.map { ($0.reward.id, $0.tags) }),
            completedTaskIDs: Set(taskRows.filter(\.isCompleted).map(\.task.id)),
            completedRewardIDs: Set(rewardRows.filter(\.isSpent).map(\.reward.id)),
            lockedTaskIDs: Set(taskRows.filter(\.isBlocked).map(\.task.id)),
            lockedRecurringTaskIDs: Set(recurringTaskRows.filter(\.isLocked).map(\.recurringTask.id)),
            lockedRewardIDs: Set(rewardRows.filter { $0.isLocked || $0.isBlocked }.map(\.reward.id)),
            hiddenStatusFilters: Set(inputs.preferences.hiddenStatusFilters),
            hiddenTagIDs: Set(inputs.preferences.hiddenTagIDs)
        )

        return OmniSearchProjection(
            queryText: inputs.queryText,
            preferences: inputs.preferences,
            snapshot: snapshot,
            rowsByID: rowsByID
        )
    }

    private static func makeTaskRows(inputs: OmniSearchProjectionInputs) -> [OmniSearchTaskRowModel] {
        let activeTasks = inputs.tasks.filter { $0.deletedAt == nil }
        let blockedTaskIDs = EntityDependencyBlockingSupport.blockedTaskIDs(
            tasks: activeTasks,
            allTasks: inputs.tasks,
            taskTaskDependencies: inputs.taskTaskDependencies,
            taskRecurringTaskDependencies: inputs.taskRecurringTaskDependencies,
            latestTaskTradesByTaskID: inputs.latestTaskTradesByTaskID,
            recurringTaskCompletionCountsByRecurringTaskID: inputs.recurringTaskCompletionCountsByRecurringTaskID,
            hasPremiumAccess: inputs.hasPremiumAccess
        )

        let completedTaskIDs = Set(inputs.latestTaskTradesByTaskID.keys)

        return activeTasks.map { task in
            OmniSearchTaskRowModel(
                task: task,
                tags: inputs.taskTagsByID[task.id, default: []],
                price: TaskPriceCalculator.calculatePrice(task: task),
                canComplete: task.canTrade && !completedTaskIDs.contains(task.id),
                isCompleted: completedTaskIDs.contains(task.id),
                isBlocked: blockedTaskIDs.contains(task.id)
            )
        }
    }

    private static func makeRecurringTaskRows(inputs: OmniSearchProjectionInputs) -> [OmniSearchRecurringTaskRowModel] {
        let activeRecurringTasks = inputs.recurringTasks.filter { $0.deletedAt == nil }

        return activeRecurringTasks.map { recurringTask in
            let completionDates = inputs.recurringTaskTradeDatesByRecurringTaskID[recurringTask.id, default: []]
            let isLocked = RecurringTaskLockout.remainingSeconds(
                recurringTask: recurringTask,
                completionDates: completionDates,
                now: inputs.now,
                hasPremiumAccess: inputs.hasPremiumAccess
            ) != nil
            let quote = RecurringTaskTradeQuote(completionDates: completionDates, pricedAt: inputs.now)
            let price = quote.totalPrice(
                recurringTask: recurringTask,
                allRecurringTasks: activeRecurringTasks,
                quantity: 1
            )

            return OmniSearchRecurringTaskRowModel(
                recurringTask: recurringTask,
                tags: inputs.recurringTaskTagsByID[recurringTask.id, default: []],
                isLocked: isLocked,
                price: price,
                quote: quote
            )
        }
    }

    private static func makeRewardRows(inputs: OmniSearchProjectionInputs) -> [OmniSearchRewardRowModel] {
        let activeRewards = inputs.rewards.filter { $0.deletedAt == nil }
        let blockedRewardIDs = EntityDependencyBlockingSupport.blockedRewardIDs(
            rewards: activeRewards,
            allTasks: inputs.tasks,
            rewardTaskDependencies: inputs.rewardTaskDependencies,
            rewardRecurringTaskDependencies: inputs.rewardRecurringTaskDependencies,
            latestTaskTradesByTaskID: inputs.latestTaskTradesByTaskID,
            recurringTaskCompletionCountsByRecurringTaskID: inputs.recurringTaskCompletionCountsByRecurringTaskID,
            hasPremiumAccess: inputs.hasPremiumAccess
        )

        return activeRewards.map { reward in
            let purchaseDates = inputs.rewardPurchaseDatesByRewardID[reward.id, default: []]
            let isLocked = RewardLockout.remainingSeconds(
                reward: reward,
                purchaseDates: purchaseDates,
                now: inputs.now,
                hasPremiumAccess: inputs.hasPremiumAccess
            ) != nil
            let quote = RewardPurchaseQuote(purchaseDates: purchaseDates, pricedAt: inputs.now)
            let price = quote.totalPrice(reward: reward, allRewards: activeRewards, quantity: 1)
            let latestPurchase = inputs.latestRewardPurchasesByRewardID[reward.id]

            return OmniSearchRewardRowModel(
                reward: reward,
                tags: inputs.rewardTagsByID[reward.id, default: []],
                price: price,
                isLocked: isLocked,
                isBlocked: blockedRewardIDs.contains(reward.id),
                isSpent: !reward.recurring && latestPurchase != nil,
                canRefund: latestPurchase != nil,
                quote: quote
            )
        }
    }

    private static func makeRowsByID(
        taskRows: [OmniSearchTaskRowModel],
        recurringTaskRows: [OmniSearchRecurringTaskRowModel],
        rewardRows: [OmniSearchRewardRowModel]
    ) -> [OmniSearchResultID: OmniSearchRowModel] {
        var rowsByID: [OmniSearchResultID: OmniSearchRowModel] = [:]
        for row in taskRows {
            rowsByID[.task(row.task.id)] = .task(row)
        }
        for row in recurringTaskRows {
            rowsByID[.recurringTask(row.recurringTask.id)] = .recurringTask(row)
        }
        for row in rewardRows {
            rowsByID[.reward(row.reward.id)] = .reward(row)
        }
        return rowsByID
    }
}
