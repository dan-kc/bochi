import Foundation

enum TaskTradeActionState: Equatable {
    case none
    case complete(amount: Int)
    case refund(amount: Int)
    case undoRefund(amount: Int)
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

        if let taskTrade {
            let amount = abs(taskTrade.amount)
            if taskTrade.isRefunded {
                return .undoRefund(amount: amount)
            }
            return .refund(amount: amount)
        }

        if !isCompleted {
            return .complete(amount: rewardPreview)
        }

        return .none
    }
}
