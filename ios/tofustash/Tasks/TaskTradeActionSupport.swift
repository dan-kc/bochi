import Foundation

enum TaskTradeActionState: Equatable {
    case none
    case complete(amount: Int)
    case refund(amount: Int)
}

enum TaskTradeActionSupport {
    static func state(
        isNewMode: Bool,
        isCompleted: Bool,
        claimed: Bool,
        taskTrade: Trade?,
        rewardPreview: Int
    ) -> TaskTradeActionState {
        guard !isNewMode, !claimed else { return .none }

        if !isCompleted {
            return taskTrade == nil ? .complete(amount: rewardPreview) : .none
        }

        if let taskTrade {
            return .refund(amount: abs(taskTrade.amount))
        }

        return .none
    }
}
