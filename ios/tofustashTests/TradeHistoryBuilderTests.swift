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
            Trade(id: "older", taskId: nil, habitId: "habit-1", rewardId: nil, amount: 50, createdAt: oldDate, updatedAt: oldDate, deletedAt: nil),
            Trade(id: "newer", taskId: nil, habitId: nil, rewardId: "reward-1", amount: -120, createdAt: newDate, updatedAt: newDate, deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            tasks: [],
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
    @Test("buildEntries keeps the trade-time name when the source item is missing")
    func keepsTradeTimeNameWhenSourceItemIsMissing() {
        let now = Date(timeIntervalSince1970: 3_000)
        let trades = [
            Trade(id: "habit-trade", taskId: nil, habitId: "missing-habit", rewardId: nil, sourceName: "Morning Run", amount: 75, createdAt: now, updatedAt: now, deletedAt: nil),
            Trade(id: "reward-trade", taskId: nil, habitId: nil, rewardId: "missing-reward", sourceName: "Ice Cream", amount: -25, createdAt: now.addingTimeInterval(-1), updatedAt: now.addingTimeInterval(-1), deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            tasks: [],
            habits: [],
            rewards: [],
            formatDate: { _ in "date" }
        )

        #expect(entries[0].title == "Morning Run")
        #expect(entries[0].isSourceDeleted)
        #expect(entries[1].title == "Ice Cream")
        #expect(entries[1].isSourceDeleted)
    }

    // Behaviour: when the source still exists locally but has been deleted,
    // the history row should keep the trade-time name and mark the source deleted.
    @Test("buildEntries marks soft-deleted sources as deleted")
    func marksSoftDeletedSourcesAsDeleted() {
        let now = Date(timeIntervalSince1970: 3_000)
        let deletedHabit = Habit(
            id: "habit-1",
            name: "Morning Run",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: now.addingTimeInterval(60),
            frequency: 1,
            difficultyTier: .medium
        )

        let entries = TradeHistoryBuilder.buildEntries(
            trades: [
                Trade(
                    id: "habit-trade",
                    taskId: nil,
                    habitId: "habit-1",
                    rewardId: nil,
                    sourceName: "Morning Run",
                    amount: 75,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil
                )
            ],
            tasks: [],
            habits: [deletedHabit],
            rewards: [],
            formatDate: { _ in "date" }
        )

        #expect(entries.map(\.title) == ["Morning Run"])
        #expect(entries.map(\.isSourceDeleted) == [true])
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
            difficultyTier: .light
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
            Trade(id: "habit-match-new", taskId: nil, habitId: "habit-1", rewardId: nil, amount: 75, createdAt: newer, updatedAt: newer, deletedAt: nil),
            Trade(id: "habit-other", taskId: nil, habitId: "habit-2", rewardId: nil, amount: 40, createdAt: older.addingTimeInterval(100), updatedAt: older.addingTimeInterval(100), deletedAt: nil),
            Trade(id: "reward-trade", taskId: nil, habitId: nil, rewardId: "reward-1", amount: -20, createdAt: older.addingTimeInterval(50), updatedAt: older.addingTimeInterval(50), deletedAt: nil),
            Trade(id: "habit-match-old", taskId: nil, habitId: "habit-1", rewardId: nil, amount: 50, createdAt: older, updatedAt: older, deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            tasks: [],
            habits: [habit, otherHabit],
            rewards: [reward],
            filter: .habit("habit-1"),
            formatDate: { _ in "date" }
        )

        #expect(entries.map { $0.id } == [RecordID("habit-match-new"), RecordID("habit-match-old")])
        #expect(entries.map { $0.title } == ["Morning Run", "Morning Run"])
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
            Trade(id: "reward-match-new", taskId: nil, habitId: nil, rewardId: "reward-1", amount: -25, createdAt: newer, updatedAt: newer, deletedAt: nil),
            Trade(id: "reward-match-deleted", taskId: nil, habitId: nil, rewardId: "reward-1", amount: -30, createdAt: newer.addingTimeInterval(-10), updatedAt: newer.addingTimeInterval(-10), deletedAt: newer),
            Trade(id: "habit-other", taskId: nil, habitId: "habit-1", rewardId: nil, amount: 60, createdAt: older.addingTimeInterval(50), updatedAt: older.addingTimeInterval(50), deletedAt: nil),
            Trade(id: "reward-match-old", taskId: nil, habitId: nil, rewardId: "reward-1", amount: -15, createdAt: older, updatedAt: older, deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            tasks: [],
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
    @Test("buildEntries keeps trade-time names when filtering deleted sources")
    func keepsTradeTimeNamesWhenFilteringDeletedSources() {
        let now = Date(timeIntervalSince1970: 3_000)
        let trades = [
            Trade(id: "habit-trade", taskId: nil, habitId: "missing-habit", rewardId: nil, sourceName: "Morning Run", amount: 75, createdAt: now, updatedAt: now, deletedAt: nil),
            Trade(id: "reward-trade", taskId: nil, habitId: nil, rewardId: "missing-reward", sourceName: "Ice Cream", amount: -25, createdAt: now, updatedAt: now, deletedAt: nil)
        ]

        let habitEntries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            tasks: [],
            habits: [],
            rewards: [],
            filter: .habit("missing-habit"),
            formatDate: { _ in "date" }
        )

        let rewardEntries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            tasks: [],
            habits: [],
            rewards: [],
            filter: .reward("missing-reward"),
            formatDate: { _ in "date" }
        )

        #expect(habitEntries.map(\.title) == ["Morning Run"])
        #expect(habitEntries.map(\.isSourceDeleted) == [true])
        #expect(rewardEntries.map(\.title) == ["Ice Cream"])
        #expect(rewardEntries.map(\.isSourceDeleted) == [true])
    }

    // Behaviour: trade history should stay historically accurate after a user
    // renames a source item, so the original trade continues showing the name
    // from the moment the trade happened.
    @Test("buildEntries prefers the trade-time source name over the current entity name")
    func prefersTradeTimeSourceNameOverCurrentEntityName() {
        let now = Date(timeIntervalSince1970: 3_000)
        let habit = Habit(
            id: "habit-1",
            name: "New Habit Name",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            frequency: 1,
            difficultyTier: .medium
        )

        let entries = TradeHistoryBuilder.buildEntries(
            trades: [
                Trade(id: "habit-trade", taskId: nil, habitId: "habit-1", rewardId: nil, sourceName: "Old Habit Name", amount: 75, createdAt: now, updatedAt: now, deletedAt: nil)
            ],
            tasks: [],
            habits: [habit],
            rewards: [],
            formatDate: { _ in "date" }
        )

        #expect(entries.map(\.title) == ["Old Habit Name"])
        #expect(entries.map(\.isSourceDeleted) == [false])
    }

    // Behaviour: task trades should resolve task names and keep completed items
    // readable in the same shared history UI as habits and rewards.
    @Test("buildEntries resolves task names and filters task history")
    func buildsTaskHistoryEntries() {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = Date(timeIntervalSince1970: 2_000)

        let task = TaskItem(
            id: "task-1",
            name: "Submit report",
            description: "",
            createdAt: oldDate,
            updatedAt: oldDate,
            deletedAt: nil,
            completedAt: newDate,
            difficultyTier: .medium,
            durationSeconds: 900,
            skipConsequence: 3,
            dueDate: nil
        )

        let trades = [
            Trade(id: "task-new", taskId: "task-1", habitId: nil, rewardId: nil, amount: 80, createdAt: newDate, updatedAt: newDate, deletedAt: nil),
            Trade(id: "task-old", taskId: "task-1", habitId: nil, rewardId: nil, amount: 60, createdAt: oldDate, updatedAt: oldDate, deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            tasks: [task],
            habits: [],
            rewards: [],
            filter: .task("task-1"),
            formatDate: { _ in "date" }
        )

        #expect(entries.map(\.id) == [RecordID("task-new"), RecordID("task-old")])
        #expect(entries.map(\.title) == ["Submit report", "Submit report"])
        #expect(entries.map(\.amountText) == ["+80", "+60"])
    }

    // Behaviour: refunded trades stay visible in history so the user can undo
    // the refund, but the row should clearly show that the tofu is inactive.
    @Test("buildEntries keeps refunded trades visible and marked")
    func keepsRefundedTradesVisibleAndMarked() {
        let createdAt = Date(timeIntervalSince1970: 2_000)
        let refundedAt = createdAt.addingTimeInterval(120)
        let reward = Reward(
            id: "reward-1",
            name: "Ice Cream",
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            maxFrequency: 1,
            damageTier: .medium
        )

        let entries = TradeHistoryBuilder.buildEntries(
            trades: [
                Trade(
                    id: "reward-refunded",
                    taskId: nil,
                    habitId: nil,
                    rewardId: "reward-1",
                    amount: -25,
                    createdAt: createdAt,
                    updatedAt: refundedAt,
                    deletedAt: nil,
                    refundedAt: refundedAt
                )
            ],
            tasks: [],
            habits: [],
            rewards: [reward],
            formatDate: { _ in "date" }
        )

        #expect(entries.count == 1)
        #expect(entries[0].title == "Ice Cream")
        #expect(entries[0].amountText == "-25")
        #expect(entries[0].isRefunded)
        #expect(entries[0].statusText == "Refunded")
    }
}
