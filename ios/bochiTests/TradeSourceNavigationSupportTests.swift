import Foundation
import Testing
@testable import bochi

struct TradeSourceNavigationSupportTests {

    // Behaviour: trade history should only offer a local source edit action
    // when the underlying task, recurringTask, or reward still exists locally.
    @Test("route returns active task source")
    func returnsActiveTaskSource() {
        let now = Date(timeIntervalSince1970: 10_000)
        let trade = Trade(
            id: "trade-1",
            taskId: "task-1",
            recurringTaskId: nil,
            rewardId: nil,
            sourceName: "Submit report",
            amount: 120,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        let task = TaskItem(
            id: "task-1",
            name: "Submit report",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            basePrice: 200,
            dueDate: nil
        )

        let route = TradeSourceNavigationSupport.route(
            for: trade,
            tasks: [task],
            recurringTasks: [],
            rewards: []
        )

        #expect(route?.taskID == "task-1")
        #expect(route?.viewActionTitle == "Change Task")
    }

    // Behaviour: deleted or missing sources should not show a view action from
    // the trade row because there is no active editor destination to open.
    @Test("route ignores deleted source")
    func ignoresDeletedSource() {
        let now = Date(timeIntervalSince1970: 10_000)
        let trade = Trade(
            id: "trade-1",
            taskId: nil,
            recurringTaskId: nil,
            rewardId: "reward-1",
            sourceName: "Ice Cream",
            amount: -40,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        let deletedReward = Reward(
            id: "reward-1",
            name: "Ice Cream",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: now.addingTimeInterval(60),
            maxFrequency: 1,
            basePrice: 500
        )

        let route = TradeSourceNavigationSupport.route(
            for: trade,
            tasks: [],
            recurringTasks: [],
            rewards: [deletedReward]
        )

        #expect(route == nil)
    }
}

private extension TradeSourceNavigationRoute {
    var taskID: RecordID? {
        guard case .task(let id) = self else { return nil }
        return id
    }
}
