import Foundation

// This file holds the presentation model for the trade-history sheet.
// Think of it like a small selector layer in React: raw store records go in,
// view-friendly rows come out.
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
        habits: [Habit],
        rewards: [Reward],
        formatDate: (Date) -> String = Self.formatDate
    ) -> [TradeHistoryEntry] {
        let habitNames = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.name) })
        let rewardNames = Dictionary(uniqueKeysWithValues: rewards.map { ($0.id, $0.name) })

        return trades
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
            .map { trade in
                let isHabitTrade = trade.habitId != nil
                let itemName: String

                if let habitId = trade.habitId {
                    itemName = habitNames[habitId] ?? "Deleted habit"
                } else if let rewardId = trade.rewardId {
                    itemName = rewardNames[rewardId] ?? "Deleted reward"
                } else {
                    itemName = "Unknown trade"
                }

                let title = "\(isHabitTrade ? "Sold" : "Bought") \(itemName)"
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

    static func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
