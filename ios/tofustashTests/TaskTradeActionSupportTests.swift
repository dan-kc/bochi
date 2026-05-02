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

    // Behaviour: a completed task should offer the reverse action using the
    // amount from the current completion trade.
    @Test("state shows refund for completed tasks")
    func showsRefundForCompletedTask() {
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
            deletedAt: nil
        )

        let state = TaskTradeActionSupport.state(
            isNewMode: false,
            isCompleted: true,
            claimed: false,
            taskTrade: trade,
            rewardPreview: 120
        )

        #expect(state == .refund(amount: 120))
    }
}
