import Foundation
import Testing
@testable import tofustash

@MainActor
struct TaskTradeActionSupportTests {

    // Behaviour: an incomplete saved task should offer a first-time completion action.
    @Test("state shows complete for incomplete tasks")
    func showsCompleteForIncompleteTask() {
        let state = TaskTradeActionSupport.state(
            isNewMode: false,
            isCompleted: false,
            claimed: false,
            taskTrade: nil,
            rewardPreview: 120
        )

        #expect(state == .complete(amount: 120))
    }

    // Behaviour: refunding a task should reopen it while still surfacing
    // undo refund as the only recovery action.
    @Test("state shows undo refund for refunded incomplete tasks")
    func showsUndoRefundForRefundedIncompleteTask() {
        let now = Date(timeIntervalSince1970: 3_000)
        let trade = Trade(
            id: "task-trade",
            taskId: "task-1",
            habitId: nil,
            rewardId: nil,
            sourceName: "Submit report",
            amount: 120,
            createdAt: now,
            updatedAt: now.addingTimeInterval(60),
            deletedAt: nil,
            refundedAt: now.addingTimeInterval(60)
        )

        let state = TaskTradeActionSupport.state(
            isNewMode: false,
            isCompleted: false,
            claimed: false,
            taskTrade: trade,
            rewardPreview: 120
        )

        #expect(state == .undoRefund(amount: 120))
    }
}
