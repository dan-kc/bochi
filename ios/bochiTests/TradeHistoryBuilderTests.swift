import Foundation
import Testing
@testable import bochi

@MainActor
struct TradeHistoryBuilderTests {
    // Behaviour: the trade sheet shows the newest events first and resolves the
    // item name the user recognises instead of exposing raw IDs.
    @Test("buildEntries sorts newest first and resolves recurringTask and reward names")
    func buildsNamedEntriesInNewestFirstOrder() {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = Date(timeIntervalSince1970: 2_000)
        let recurringTask = makeRecurringTask(id: "recurringTask-1", name: "Morning Run", createdAt: oldDate)
        let reward = makeReward(id: "reward-1", name: "Ice Cream", createdAt: oldDate)

        let trades = [
            Trade(id: "older", taskId: nil, recurringTaskId: "recurringTask-1", rewardId: nil, amount: 50, createdAt: oldDate, updatedAt: oldDate, deletedAt: nil),
            Trade(id: "newer", taskId: nil, recurringTaskId: nil, rewardId: "reward-1", amount: -120, createdAt: newDate, updatedAt: newDate, deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            tasks: [],
            recurringTasks: [recurringTask],
            rewards: [reward],
            formatDate: { date in date == newDate ? "new" : "old" }
        )

        #expect(entries.map { $0.id } == [RecordID("newer"), RecordID("older")])
        #expect(entries[0].title == "Ice Cream")
        #expect(entries[0].amountText == "-120")
        #expect(entries[1].title == "Morning Run")
        #expect(entries[1].amountText == "+50")
    }

    // Behaviour: old history stays legible even after the underlying recurringTask or
    // reward has been deleted from the active lists.
    @Test("buildEntries keeps the trade-time name when the source item is missing")
    func keepsTradeTimeNameWhenSourceItemIsMissing() {
        let now = Date(timeIntervalSince1970: 3_000)
        let trades = [
            Trade(id: "recurringTask-trade", taskId: nil, recurringTaskId: "missing-recurringTask", rewardId: nil, sourceName: "Morning Run", amount: 75, createdAt: now, updatedAt: now, deletedAt: nil),
            Trade(id: "reward-trade", taskId: nil, recurringTaskId: nil, rewardId: "missing-reward", sourceName: "Ice Cream", amount: -25, createdAt: now.addingTimeInterval(-1), updatedAt: now.addingTimeInterval(-1), deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            tasks: [],
            recurringTasks: [],
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
        let deletedRecurringTask = makeRecurringTask(
            id: "recurringTask-1",
            name: "Morning Run",
            createdAt: now,
            deletedAt: now.addingTimeInterval(60)
        )

        let entries = TradeHistoryBuilder.buildEntries(
            trades: [
                Trade(id: "recurringTask-trade", taskId: nil, recurringTaskId: "recurringTask-1", rewardId: nil, sourceName: "Morning Run", amount: 75, createdAt: now, updatedAt: now, deletedAt: nil)
            ],
            tasks: [],
            recurringTasks: [deletedRecurringTask],
            rewards: [],
            formatDate: { _ in "date" }
        )

        #expect(entries.map { $0.title } == ["Morning Run"])
        #expect(entries.map { $0.isSourceDeleted } == [true])
    }

    // Behaviour: trade history shows that a one-time adjustment was applied
    // without exposing the stored multiplier to the user.
    @Test("buildEntries shows the trade-time one-time adjustment snapshot")
    func showsTradeTimeOneTimeAdjustmentSnapshot() {
        let now = Date(timeIntervalSince1970: 3_500)
        let recurringTask = makeRecurringTask(id: "recurringTask-1", name: "Morning Run", createdAt: now)

        let entries = TradeHistoryBuilder.buildEntries(
            trades: [
                Trade(
                    id: "recurringTask-trade",
                    taskId: nil,
                    recurringTaskId: "recurringTask-1",
                    rewardId: nil,
                    amount: 200,
                    adjustmentBaseAmount: 100,
                    oneTimeAdjustmentMultiplier: 2,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil
                )
            ],
            tasks: [],
            recurringTasks: [recurringTask],
            rewards: [],
            formatDate: { _ in "date" }
        )

        let entry = entries[0]
        #expect(entry.amountText == "+200")
        #expect(entry.originalAmountText == "+100")
        #expect(entry.adjustmentTexts == ["One-time adjustment"])
    }

    // Behaviour: opening history from a recurringTask should only show that recurringTask's
    // own claims, even when other recurringTasks and rewards have trade history.
    @Test("buildEntries filters to the selected recurringTask")
    func filtersToSelectedRecurringTask() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let recurringTask = makeRecurringTask(id: "recurringTask-1", name: "Morning Run", createdAt: older)
        let otherRecurringTask = makeRecurringTask(id: "recurringTask-2", name: "Read", createdAt: older)
        let reward = makeReward(id: "reward-1", name: "Ice Cream", createdAt: older)

        let trades = [
            Trade(id: "recurringTask-match-new", taskId: nil, recurringTaskId: "recurringTask-1", rewardId: nil, amount: 75, createdAt: newer, updatedAt: newer, deletedAt: nil),
            Trade(id: "recurringTask-other", taskId: nil, recurringTaskId: "recurringTask-2", rewardId: nil, amount: 40, createdAt: older.addingTimeInterval(100), updatedAt: older.addingTimeInterval(100), deletedAt: nil),
            Trade(id: "reward-trade", taskId: nil, recurringTaskId: nil, rewardId: "reward-1", amount: -20, createdAt: older.addingTimeInterval(50), updatedAt: older.addingTimeInterval(50), deletedAt: nil),
            Trade(id: "recurringTask-match-old", taskId: nil, recurringTaskId: "recurringTask-1", rewardId: nil, amount: 50, createdAt: older, updatedAt: older, deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            tasks: [],
            recurringTasks: [recurringTask, otherRecurringTask],
            rewards: [reward],
            filter: .recurringTask("recurringTask-1"),
            formatDate: { _ in "date" }
        )

        #expect(entries.map { $0.id } == [RecordID("recurringTask-match-new"), RecordID("recurringTask-match-old")])
        #expect(entries.map { $0.title } == ["Morning Run", "Morning Run"])
    }

    // Behaviour: opening history from a reward should ignore unrelated trades
    // and continue hiding deleted purchases from the visible list.
    @Test("buildEntries filters to the selected reward and excludes deleted trades")
    func filtersToSelectedRewardAndExcludesDeletedTrades() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let recurringTask = makeRecurringTask(id: "recurringTask-1", name: "Morning Run", createdAt: older)
        let reward = makeReward(id: "reward-1", name: "Ice Cream", createdAt: older)

        let trades = [
            Trade(id: "reward-match-new", taskId: nil, recurringTaskId: nil, rewardId: "reward-1", amount: -25, createdAt: newer, updatedAt: newer, deletedAt: nil),
            Trade(id: "reward-match-deleted", taskId: nil, recurringTaskId: nil, rewardId: "reward-1", amount: -30, createdAt: newer.addingTimeInterval(-10), updatedAt: newer.addingTimeInterval(-10), deletedAt: newer),
            Trade(id: "recurringTask-other", taskId: nil, recurringTaskId: "recurringTask-1", rewardId: nil, amount: 60, createdAt: older.addingTimeInterval(50), updatedAt: older.addingTimeInterval(50), deletedAt: nil),
            Trade(id: "reward-match-old", taskId: nil, recurringTaskId: nil, rewardId: "reward-1", amount: -15, createdAt: older, updatedAt: older, deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            tasks: [],
            recurringTasks: [recurringTask],
            rewards: [reward],
            filter: .reward("reward-1"),
            formatDate: { _ in "date" }
        )

        #expect(entries.map { $0.id } == [RecordID("reward-match-new"), RecordID("reward-match-old")])
        #expect(entries.map { $0.title } == ["Ice Cream", "Ice Cream"])
        #expect(entries.map { $0.amountText } == ["-25", "-15"])
    }

    // Behaviour: trade history should stay historically accurate after a user
    // renames a source item, so the original trade continues showing the name
    // from the moment the trade happened.
    @Test("buildEntries prefers the trade-time source name over the current entity name")
    func prefersTradeTimeSourceNameOverCurrentEntityName() {
        let now = Date(timeIntervalSince1970: 3_000)
        let recurringTask = makeRecurringTask(id: "recurringTask-1", name: "New RecurringTask Name", createdAt: now)

        let entries = TradeHistoryBuilder.buildEntries(
            trades: [
                Trade(id: "recurringTask-trade", taskId: nil, recurringTaskId: "recurringTask-1", rewardId: nil, sourceName: "Old RecurringTask Name", amount: 75, createdAt: now, updatedAt: now, deletedAt: nil)
            ],
            tasks: [],
            recurringTasks: [recurringTask],
            rewards: [],
            formatDate: { _ in "date" }
        )

        #expect(entries.map { $0.title } == ["Old RecurringTask Name"])
        #expect(entries.map { $0.isSourceDeleted } == [false])
    }

    // Behaviour: task trades should resolve task names and keep completed items
    // readable in the same shared history UI as recurringTasks and rewards.
    @Test("buildEntries resolves task names and filters task history")
    func buildsTaskHistoryEntries() {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = Date(timeIntervalSince1970: 2_000)
        let task = makeTask(id: "task-1", name: "Submit report", createdAt: oldDate)

        let trades = [
            Trade(id: "task-new", taskId: "task-1", recurringTaskId: nil, rewardId: nil, amount: 80, createdAt: newDate, updatedAt: newDate, deletedAt: nil),
            Trade(id: "task-old", taskId: "task-1", recurringTaskId: nil, rewardId: nil, amount: 60, createdAt: oldDate, updatedAt: oldDate, deletedAt: nil)
        ]

        let entries = TradeHistoryBuilder.buildEntries(
            trades: trades,
            tasks: [task],
            recurringTasks: [],
            rewards: [],
            filter: .task("task-1"),
            formatDate: { _ in "date" }
        )

        #expect(entries.map { $0.id } == [RecordID("task-new"), RecordID("task-old")])
        #expect(entries.map { $0.title } == ["Submit report", "Submit report"])
        #expect(entries.map { $0.amountText } == ["+80", "+60"])
    }

    // Behaviour: refund trades stay visible as their own ledger rows so the
    // user can see the reversal rather than a mutated original entry.
    @Test("buildEntries keeps refund trades visible and marked")
    func keepsRefundTradesVisibleAndMarked() {
        let createdAt = Date(timeIntervalSince1970: 2_000)
        let reward = makeReward(id: "reward-1", name: "Ice Cream", createdAt: createdAt)

        let entries = TradeHistoryBuilder.buildEntries(
            trades: [
                Trade(
                    id: "reward-refund",
                    taskId: nil,
                    recurringTaskId: nil,
                    rewardId: "reward-1",
                    amount: 25,
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    deletedAt: nil,
                    refundsTradeId: "reward-trade"
                )
            ],
            tasks: [],
            recurringTasks: [],
            rewards: [reward],
            formatDate: { _ in "date" }
        )

        #expect(entries.count == 1)
        #expect(entries[0].title == "Ice Cream")
        #expect(entries[0].amountText == "+25")
        #expect(entries[0].isRefunded)
        #expect(entries[0].statusText == "Refund")
    }

    // Behaviour: vault rows use their fixed-point vault amount so fractional
    // interest appears in history instead of a zero normal-balance amount.
    @Test("buildEntries formats vault micro amounts")
    func formatsVaultMicroAmounts() {
        let createdAt = Date(timeIntervalSince1970: 2_000)

        let entries = TradeHistoryBuilder.buildEntries(
            trades: [
                Trade(
                    id: "vault-interest",
                    taskId: nil,
                    recurringTaskId: nil,
                    rewardId: nil,
                    sourceName: "Vault interest",
                    amount: 0,
                    vaultAmountMicro: 22_700,
                    tradeKind: .vaultInterest,
                    vaultInterestHour: createdAt,
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    deletedAt: nil
                )
            ],
            tasks: [],
            recurringTasks: [],
            rewards: [],
            formatDate: { _ in "date" }
        )

        #expect(entries.count == 1)
        #expect(entries[0].title == "Bank interest")
        #expect(entries[0].amountText == "+0.0227")
        #expect(entries[0].isPositive)
        #expect(entries[0].statusText == "Bank Interest")
    }
}

private func makeTask(id: RecordID, name: String, createdAt: Date) -> TaskItem {
    TaskItem(
        id: id,
        name: name,
        description: "",
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: nil,
        basePrice: 200,
        dueDate: nil
    )
}

private func makeRecurringTask(
    id: RecordID,
    name: String,
    createdAt: Date,
    deletedAt: Date? = nil
) -> RecurringTask {
    RecurringTask(
        id: id,
        name: name,
        description: "",
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: deletedAt,
        frequency: 1,
        basePrice: 100
    )
}

private func makeReward(id: RecordID, name: String, createdAt: Date) -> Reward {
    Reward(
        id: id,
        name: name,
        description: "",
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: nil,
        maxFrequency: 1,
        basePrice: 500
    )
}
