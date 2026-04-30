import Foundation

// This file holds the presentation model for the trade-history sheet.
// Think of it like a small selector layer in React: raw store records go in,
// view-friendly rows come out.
enum TradeHistoryFilter: Equatable {
    case all
    case task(RecordID)
    case habit(RecordID)
    case reward(RecordID)
}

struct TradeHistoryEntry: Identifiable, Equatable {
    let id: RecordID
    let title: String
    let dateText: String
    let amountText: String
    let isPositive: Bool
    let isRefunded: Bool
    let isSourceDeleted: Bool
    let statusText: String?
}

struct TradeSourceSummary: Equatable {
    let kindLabel: String
    let name: String
    let isDeleted: Bool
}

enum TradeHistoryBuilder {
    // Maps raw trades into rows the sheet can render directly.
    // Keeping this logic outside the SwiftUI view makes the UI code smaller
    // and gives us a stable place to write behaviour-focused tests.
    static func buildEntries(
        trades: [Trade],
        tasks: [TaskItem],
        habits: [Habit],
        rewards: [Reward],
        filter: TradeHistoryFilter = .all,
        formatDate: (Date) -> String = Self.formatDate
    ) -> [TradeHistoryEntry] {
        let taskNames = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.name) })
        let activeTaskIDs = Set(tasks.filter { $0.deletedAt == nil }.map(\.id))
        let habitNames = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.name) })
        let activeHabitIDs = Set(habits.filter { $0.deletedAt == nil }.map(\.id))
        let rewardNames = Dictionary(uniqueKeysWithValues: rewards.map { ($0.id, $0.name) })
        let activeRewardIDs = Set(rewards.filter { $0.deletedAt == nil }.map(\.id))

        return trades
            .filter { trade in
                guard trade.deletedAt == nil else { return false }

                switch filter {
                case .all:
                    return true
                case .task(let taskID):
                    return trade.taskId == taskID
                case .habit(let habitID):
                    return trade.habitId == habitID
                case .reward(let rewardID):
                    return trade.rewardId == rewardID
                }
            }
            .sorted { $0.createdAt > $1.createdAt }
            .map { trade in
                let source = sourceSummary(
                    for: trade,
                    taskNames: taskNames,
                    activeTaskIDs: activeTaskIDs,
                    habitNames: habitNames,
                    activeHabitIDs: activeHabitIDs,
                    rewardNames: rewardNames,
                    activeRewardIDs: activeRewardIDs
                )
                let isPositive = trade.amount >= 0
                let amountText = "\(isPositive ? "+" : "-")\(abs(trade.amount))"

                return TradeHistoryEntry(
                    id: trade.id,
                    title: source.name,
                    dateText: formatDate(trade.createdAt),
                    amountText: amountText,
                    isPositive: isPositive,
                    isRefunded: trade.refundedAt != nil,
                    isSourceDeleted: source.isDeleted,
                    statusText: trade.refundedAt != nil ? "Refunded" : nil
                )
            }
    }

    static func sourceSummary(
        for trade: Trade,
        tasks: [TaskItem],
        habits: [Habit],
        rewards: [Reward]
    ) -> TradeSourceSummary {
        let taskNames = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.name) })
        let activeTaskIDs = Set(tasks.filter { $0.deletedAt == nil }.map(\.id))
        let habitNames = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.name) })
        let activeHabitIDs = Set(habits.filter { $0.deletedAt == nil }.map(\.id))
        let rewardNames = Dictionary(uniqueKeysWithValues: rewards.map { ($0.id, $0.name) })
        let activeRewardIDs = Set(rewards.filter { $0.deletedAt == nil }.map(\.id))

        return sourceSummary(
            for: trade,
            taskNames: taskNames,
            activeTaskIDs: activeTaskIDs,
            habitNames: habitNames,
            activeHabitIDs: activeHabitIDs,
            rewardNames: rewardNames,
            activeRewardIDs: activeRewardIDs
        )
    }

    nonisolated static func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private static func sourceSummary(
        for trade: Trade,
        taskNames: [RecordID: String],
        activeTaskIDs: Set<RecordID>,
        habitNames: [RecordID: String],
        activeHabitIDs: Set<RecordID>,
        rewardNames: [RecordID: String],
        activeRewardIDs: Set<RecordID>
    ) -> TradeSourceSummary {
        if let taskId = trade.taskId {
            return TradeSourceSummary(
                kindLabel: "Task",
                name: trade.sourceName ?? taskNames[taskId] ?? "Deleted task",
                isDeleted: !activeTaskIDs.contains(taskId)
            )
        }

        if let habitId = trade.habitId {
            return TradeSourceSummary(
                kindLabel: "Habit",
                name: trade.sourceName ?? habitNames[habitId] ?? "Deleted habit",
                isDeleted: !activeHabitIDs.contains(habitId)
            )
        }

        if let rewardId = trade.rewardId {
            return TradeSourceSummary(
                kindLabel: "Reward",
                name: trade.sourceName ?? rewardNames[rewardId] ?? "Deleted reward",
                isDeleted: !activeRewardIDs.contains(rewardId)
            )
        }

        return TradeSourceSummary(
            kindLabel: "Source",
            name: trade.sourceName ?? "Unknown trade",
            isDeleted: false
        )
    }
}
