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
            difficultyTier: .medium
        )

        let reward = Reward(
            id: "reward-1",
            name: "Ice Cream",
            description: "",
            createdAt: oldDate,
            updatedAt: oldDate,
            deletedAt: nil,
            maxFrequency: 1,
            damageTier: .medium
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

        #expect(entries.map(\.id) == [RecordID("newer"), RecordID("older")])
        #expect(entries[0].title == "Ice Cream")
        #expect(entries[0].amountText == "-120")
        #expect(entries[1].title == "Morning Run")
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

        #expect(entries[0].title == "Deleted habit")
        #expect(entries[1].title == "Deleted reward")
    }

    // Behaviour: opening history from a habit should only show that habit's
    // own claims, even when other habits and rewards have trade history.
    @Test("buildEntries filters to the selected habit")
    func filtersToSelectedHabit() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        let habit = Habit(
            id: "habit-1",
            name: "Morning Run",
            description: "",
            createdAt: older,
            updatedAt: older,
            deletedAt: nil,
            frequency: 1,
            difficultyTier: .medium
        )

        let otherHabit = Habit(
            id: "habit-2",
            name: "Read",
            description: "",
            createdAt: older,
            updatedAt: older,
            deletedAt: nil,
            frequency: 1,
            difficultyTier: .easy
        )

        let reward = Reward(
            id: "reward-1",
            name: "Ice Cream",
            description: "",
            createdAt: older,
            updatedAt: older,
            deletedAt: nil,
            maxFrequency: 1,
            damageTier: .medium
        )

        let trades = [
            Trade(id: "habit-match-new", habitId: "habit-1", rewardId: nil, amount: 75, createdAt: newer, updatedAt: newer, deletedAt: nil),
            Trade(id: "habit-other", habitId: "habit-2", rewardId: nil, amount: 40, createdAt: older.addingTimeInterval(100), updatedAt: older.addingTimeInterval(100), deletedAt: nil),
            Trade(id: "reward-trade", habitId: nil, rewardId: "reward-1", amount: -20, createdAt: older.addingTimeInterval(50), updatedAt: older.addingTimeInterval(50), deletedAt: nil),
            Trade(id: "habit-match-old", habitId: "habit-1", rewardId: nil, amount: 50, createdAt: older, updatedAt: older, deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            habits: [habit, otherHabit],
            rewards: [reward],
            filter: .habit("habit-1"),
            formatDate: { _ in "date" }
        )

        #expect(entries.map(\.id) == [RecordID("habit-match-new"), RecordID("habit-match-old")])
        #expect(entries.map(\.title) == ["Morning Run", "Morning Run"])
    }

    // Behaviour: opening history from a reward should ignore unrelated trades
    // and continue hiding deleted purchases from the visible list.
    @Test("buildEntries filters to the selected reward and excludes deleted trades")
    func filtersToSelectedRewardAndExcludesDeletedTrades() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        let habit = Habit(
            id: "habit-1",
            name: "Morning Run",
            description: "",
            createdAt: older,
            updatedAt: older,
            deletedAt: nil,
            frequency: 1,
            difficultyTier: .medium
        )

        let reward = Reward(
            id: "reward-1",
            name: "Ice Cream",
            description: "",
            createdAt: older,
            updatedAt: older,
            deletedAt: nil,
            maxFrequency: 1,
            damageTier: .medium
        )

        let trades = [
            Trade(id: "reward-match-new", habitId: nil, rewardId: "reward-1", amount: -25, createdAt: newer, updatedAt: newer, deletedAt: nil),
            Trade(id: "reward-match-deleted", habitId: nil, rewardId: "reward-1", amount: -30, createdAt: newer.addingTimeInterval(-10), updatedAt: newer.addingTimeInterval(-10), deletedAt: newer),
            Trade(id: "habit-other", habitId: "habit-1", rewardId: nil, amount: 60, createdAt: older.addingTimeInterval(50), updatedAt: older.addingTimeInterval(50), deletedAt: nil),
            Trade(id: "reward-match-old", habitId: nil, rewardId: "reward-1", amount: -15, createdAt: older, updatedAt: older, deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            habits: [habit],
            rewards: [reward],
            filter: .reward("reward-1"),
            formatDate: { _ in "date" }
        )

        #expect(entries.map(\.id) == [RecordID("reward-match-new"), RecordID("reward-match-old")])
        #expect(entries.map(\.title) == ["Ice Cream", "Ice Cream"])
        #expect(entries.map(\.amountText) == ["-25", "-15"])
    }

    // Behaviour: filtered history should still stay readable after the edited
    // habit or reward has been deleted from the active list.
    @Test("buildEntries keeps deleted fallback labels when filtering")
    func keepsDeletedFallbackLabelsWhenFiltering() {
        let now = Date(timeIntervalSince1970: 3_000)
        let trades = [
            Trade(id: "habit-trade", habitId: "missing-habit", rewardId: nil, amount: 75, createdAt: now, updatedAt: now, deletedAt: nil),
            Trade(id: "reward-trade", habitId: nil, rewardId: "missing-reward", amount: -25, createdAt: now, updatedAt: now, deletedAt: nil)
        ]

        let habitEntries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            habits: [],
            rewards: [],
            filter: .habit("missing-habit"),
            formatDate: { _ in "date" }
        )

        let rewardEntries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            habits: [],
            rewards: [],
            filter: .reward("missing-reward"),
            formatDate: { _ in "date" }
        )

        #expect(habitEntries.map(\.title) == ["Deleted habit"])
        #expect(rewardEntries.map(\.title) == ["Deleted reward"])
    }
}
