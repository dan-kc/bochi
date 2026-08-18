import Foundation

enum TradeSourceNavigationRoute: Equatable {
    case task(RecordID)
    case recurringTask(RecordID)
    case reward(RecordID)

    var viewActionTitle: String {
        switch self {
        case .task:
            return "Change Task"
        case .recurringTask:
            return "Change Recurring Task"
        case .reward:
            return "Change Reward"
        }
    }
}

enum TradeSourceNavigationSupport {
    static func route(
        for trade: Trade,
        tasks: [TaskItem],
        recurringTasks: [RecurringTask],
        rewards: [Reward]
    ) -> TradeSourceNavigationRoute? {
        if let taskID = trade.taskId,
           tasks.contains(where: { $0.id == taskID && $0.deletedAt == nil }) {
            return .task(taskID)
        }

        if let recurringTaskID = trade.recurringTaskId,
           recurringTasks.contains(where: { $0.id == recurringTaskID && $0.deletedAt == nil }) {
            return .recurringTask(recurringTaskID)
        }

        if let rewardID = trade.rewardId,
           rewards.contains(where: { $0.id == rewardID && $0.deletedAt == nil }) {
            return .reward(rewardID)
        }

        return nil
    }
}
