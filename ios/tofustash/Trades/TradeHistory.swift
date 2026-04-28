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
        let habitNames = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.name) })
        let rewardNames = Dictionary(uniqueKeysWithValues: rewards.map { ($0.id, $0.name) })

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
                let itemName: String

                if let taskId = trade.taskId {
                    itemName = taskNames[taskId] ?? "Deleted task"
                } else if let habitId = trade.habitId {
                    itemName = habitNames[habitId] ?? "Deleted habit"
                } else if let rewardId = trade.rewardId {
                    itemName = rewardNames[rewardId] ?? "Deleted reward"
                } else {
                    itemName = "Unknown trade"
                }

                let title = "\(itemName)"
                let isPositive = trade.amount >= 0
                let amountText = "\(isPositive ? "+" : "-")\(abs(trade.amount))"

                return TradeHistoryEntry(
                    id: trade.id,
                    title: title,
                    dateText: formatDate(trade.createdAt),
                    amountText: amountText,
                    isPositive: isPositive
                )
            }
    }

    nonisolated static func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
