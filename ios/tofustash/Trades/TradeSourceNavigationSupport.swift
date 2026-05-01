import Foundation

enum TradeSourceNavigationRoute: Equatable {
    case task(RecordID)
    case habit(RecordID)
    case reward(RecordID)

    var viewActionTitle: String {
        switch self {
        case .task:
            return "View Task"
        case .habit:
            return "View Habit"
        case .reward:
            return "View Reward"
        }
    }
}

enum TradeSourceNavigationSupport {
    static func route(
        for trade: Trade,
        tasks: [TaskItem],
        habits: [Habit],
        rewards: [Reward]
    ) -> TradeSourceNavigationRoute? {
        if let taskID = trade.taskId,
           tasks.contains(where: { $0.id == taskID && $0.deletedAt == nil }) {
            return .task(taskID)
        }

        if let habitID = trade.habitId,
           habits.contains(where: { $0.id == habitID && $0.deletedAt == nil }) {
            return .habit(habitID)
        }

        if let rewardID = trade.rewardId,
           rewards.contains(where: { $0.id == rewardID && $0.deletedAt == nil }) {
            return .reward(rewardID)
        }

        return nil
    }
}
