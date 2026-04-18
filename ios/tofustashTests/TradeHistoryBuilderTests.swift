import Foundation
import Testing
@testable import tofustash

@MainActor
struct TradeHistoryBuilderTests {

    // Behaviour: the trade sheet shows the newest events first and resolves the
    // item name the user recognises instead of exposing raw IDs.
    @Test("buildEntries sorts newest first and resolves habit and reward names")
    func buildsNamedEntriesInNewestFirstOrder() {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = Date(timeIntervalSince1970: 2_000)

        let habit = Habit(
            id: "habit-1",
            name: "Morning Run",
            description: "",
            createdAt: oldDate,
            updatedAt: oldDate,
            deletedAt: nil,
            frequency: 1,
            difficultyRank: "m"
        )

        let reward = Reward(
            id: "reward-1",
            name: "Ice Cream",
            description: "",
            createdAt: oldDate,
            updatedAt: oldDate,
            deletedAt: nil,
            maxFrequency: 1,
            damageRank: "m"
        )

        let trades = [
            Trade(id: "older", habitId: "habit-1", rewardId: nil, amount: 50, createdAt: oldDate, updatedAt: oldDate, deletedAt: nil),
            Trade(id: "newer", habitId: nil, rewardId: "reward-1", amount: -120, createdAt: newDate, updatedAt: newDate, deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            habits: [habit],
            rewards: [reward],
            formatDate: { date in date == newDate ? "new" : "old" }
        )

        #expect(entries.map(\.id) == ["newer", "older"])
        #expect(entries[0].title == "Bought Ice Cream")
        #expect(entries[0].amountText == "-120")
        #expect(entries[1].title == "Sold Morning Run")
        #expect(entries[1].amountText == "+50")
    }

    // Behaviour: old history stays legible even after the underlying habit or
    // reward has been deleted from the active lists.
    @Test("buildEntries falls back to deleted labels when the source item is missing")
    func buildsDeletedFallbackLabels() {
        let now = Date(timeIntervalSince1970: 3_000)
        let trades = [
            Trade(id: "habit-trade", habitId: "missing-habit", rewardId: nil, amount: 75, createdAt: now, updatedAt: now, deletedAt: nil),
            Trade(id: "reward-trade", habitId: nil, rewardId: "missing-reward", amount: -25, createdAt: now.addingTimeInterval(-1), updatedAt: now.addingTimeInterval(-1), deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            habits: [],
            rewards: [],
            formatDate: { _ in "date" }
        )

        #expect(entries[0].title == "Sold Deleted habit")
        #expect(entries[1].title == "Bought Deleted reward")
    }
}
