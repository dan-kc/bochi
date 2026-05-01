import Foundation
import Testing
@testable import tofustash

struct TradeSourceNavigationSupportTests {

    // Behaviour: trade history should only offer source navigation when the
    // underlying task, habit, or reward still exists locally.
    @Test("route returns active task source")
    func returnsActiveTaskSource() {
        let now = Date(timeIntervalSince1970: 10_000)
        let trade = Trade(
            id: "trade-1",
            taskId: "task-1",
            habitId: nil,
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
            completedAt: nil,
            difficultyTier: nil,
            durationSeconds: nil,
            skipConsequence: nil,
            dueDate: nil
        )

        let route = TradeSourceNavigationSupport.route(
            for: trade,
            tasks: [task],
            habits: [],
            rewards: []
        )

        #expect(route == .task("task-1"))
        #expect(route?.viewActionTitle == "View Task")
    }

    // Behaviour: deleted or missing sources should not show a view action from
    // the trade row because there is no active editor destination to open.
    @Test("route ignores deleted source")
    func ignoresDeletedSource() {
        let now = Date(timeIntervalSince1970: 10_000)
        let trade = Trade(
            id: "trade-1",
            taskId: nil,
            habitId: nil,
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
            damageTier: .medium
        )

        let route = TradeSourceNavigationSupport.route(
            for: trade,
            tasks: [],
            habits: [],
            rewards: [deletedReward]
        )

        #expect(route == nil)
    }
}
