import Foundation

// This file holds the presentation model for the trade-history sheet.
// Think of it like a small selector layer in React: raw store records go in,
// view-friendly rows come out.
enum TradeHistoryFilter: Equatable {
    case all
    case task(RecordID)
    case recurringTask(RecordID)
    case reward(RecordID)
}

struct TradeHistoryEntry: Identifiable, Equatable {
    let id: RecordID
    let title: String
    let dateText: String
    let amountText: String
    let originalAmountText: String?
    let isPositive: Bool
    let isRefunded: Bool
    let isSourceDeleted: Bool
    let statusText: String?
    let adjustmentTexts: [String]
}

struct TradeSourceSummary: Equatable {
    let kindLabel: String
    let name: String
    let isDeleted: Bool
}

enum TradeHistoryBuilder {
    private struct SourceIndexes {
        let taskNames: [RecordID: String]
        let activeTaskIDs: Set<RecordID>
        let recurringTaskNames: [RecordID: String]
        let activeRecurringTaskIDs: Set<RecordID>
        let rewardNames: [RecordID: String]
        let activeRewardIDs: Set<RecordID>

        init(tasks: [TaskItem], recurringTasks: [RecurringTask], rewards: [Reward]) {
            taskNames = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.name) })
            activeTaskIDs = Set(tasks.filter { $0.deletedAt == nil }.map(\.id))
            recurringTaskNames = Dictionary(uniqueKeysWithValues: recurringTasks.map { ($0.id, $0.name) })
            activeRecurringTaskIDs = Set(recurringTasks.filter { $0.deletedAt == nil }.map(\.id))
            rewardNames = Dictionary(uniqueKeysWithValues: rewards.map { ($0.id, $0.name) })
            activeRewardIDs = Set(rewards.filter { $0.deletedAt == nil }.map(\.id))
        }
    }

    // Maps raw trades into rows the sheet can render directly.
    // Keeping this logic outside the SwiftUI view makes the UI code smaller
    // and gives us a stable place to write behaviour-focused tests.
    static func buildEntries(
        trades: [Trade],
        tasks: [TaskItem],
        recurringTasks: [RecurringTask],
        rewards: [Reward],
        filter: TradeHistoryFilter = .all,
        sortNewestFirst: Bool = true,
        formatDate: (Date) -> String = Self.formatDate
    ) -> [TradeHistoryEntry] {
        let sourceIndexes = SourceIndexes(tasks: tasks, recurringTasks: recurringTasks, rewards: rewards)

        let filteredTrades = trades
            .filter { trade in
                guard trade.deletedAt == nil else { return false }

                switch filter {
                case .all:
                    return true
                case .task(let taskID):
                    return trade.taskId == taskID
                case .recurringTask(let recurringTaskID):
                    return trade.recurringTaskId == recurringTaskID
                case .reward(let rewardID):
                    return trade.rewardId == rewardID
                }
            }

        let orderedTrades = sortNewestFirst
            ? filteredTrades.sorted { $0.createdAt > $1.createdAt }
            : filteredTrades

        return orderedTrades
            .map { trade in
                let source = sourceSummary(for: trade, indexes: sourceIndexes)
                let displayAmount = displayAmount(for: trade)
                let isPositive = displayAmount.isPositive
                let originalAmountText = trade.adjustmentBaseAmount.map { baseAmount in
                    "\(baseAmount >= 0 ? "+" : "-")\(abs(baseAmount))"
                }
                var adjustmentTexts: [String] = []
                if trade.oneTimeAdjustmentMultiplier != nil {
                    adjustmentTexts.append("One-time adjustment")
                }

                return TradeHistoryEntry(
                    id: trade.id,
                    title: source.name,
                    dateText: formatDate(trade.createdAt),
                    amountText: displayAmount.text,
                    originalAmountText: originalAmountText,
                    isPositive: isPositive,
                    isRefunded: trade.isRefundTrade,
                    isSourceDeleted: source.isDeleted,
                    statusText: statusText(for: trade),
                    adjustmentTexts: adjustmentTexts
                )
            }
    }

    static func sourceSummary(
        for trade: Trade,
        tasks: [TaskItem],
        recurringTasks: [RecurringTask],
        rewards: [Reward]
    ) -> TradeSourceSummary {
        sourceSummary(for: trade, indexes: SourceIndexes(tasks: tasks, recurringTasks: recurringTasks, rewards: rewards))
    }

    nonisolated static func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private static func sourceSummary(
        for trade: Trade,
        indexes: SourceIndexes
    ) -> TradeSourceSummary {
        switch trade.tradeKind {
        case .vaultDeposit:
            return TradeSourceSummary(
                kindLabel: "Bank",
                name: bankSourceName(trade.sourceName, fallback: "Bank deposit"),
                isDeleted: false
            )
        case .vaultInterest:
            return TradeSourceSummary(
                kindLabel: "Bank",
                name: bankSourceName(trade.sourceName, fallback: "Bank interest"),
                isDeleted: false
            )
        case .taskCompletion, .recurringTaskCompletion, .rewardPurchase, .vaultRewardPurchase:
            break
        }

        if let taskId = trade.taskId {
            return TradeSourceSummary(
                kindLabel: "Task",
                name: trade.sourceName ?? indexes.taskNames[taskId] ?? "Deleted task",
                isDeleted: !indexes.activeTaskIDs.contains(taskId)
            )
        }

        if let recurringTaskId = trade.recurringTaskId {
            return TradeSourceSummary(
                kindLabel: "Recurring Task",
                name: trade.sourceName ?? indexes.recurringTaskNames[recurringTaskId] ?? "Deleted recurring task",
                isDeleted: !indexes.activeRecurringTaskIDs.contains(recurringTaskId)
            )
        }

        if let rewardId = trade.rewardId {
            return TradeSourceSummary(
                kindLabel: "Reward",
                name: trade.sourceName ?? indexes.rewardNames[rewardId] ?? "Deleted reward",
                isDeleted: !indexes.activeRewardIDs.contains(rewardId)
            )
        }

        return TradeSourceSummary(
            kindLabel: "Source",
            name: trade.sourceName ?? "Unknown trade",
            isDeleted: false
        )
    }

    private static func statusText(for trade: Trade) -> String? {
        if trade.isRefundTrade { return "Refund" }
        switch trade.tradeKind {
        case .vaultDeposit:
            return "Bank Deposit"
        case .vaultInterest:
            return "Bank Interest"
        case .vaultRewardPurchase:
            return "Bank Purchase"
        case .taskCompletion, .recurringTaskCompletion, .rewardPurchase:
            return nil
        }
    }

    private static func bankSourceName(_ sourceName: String?, fallback: String) -> String {
        switch sourceName {
        case "Vault deposit":
            return "Bank deposit"
        case "Vault interest":
            return "Bank interest"
        case let sourceName?:
            return sourceName
        case nil:
            return fallback
        }
    }

    private static func displayAmount(for trade: Trade) -> (text: String, isPositive: Bool) {
        if trade.tradeKind.isVault, let vaultAmountMicro = trade.vaultAmountMicro {
            let isPositive = vaultAmountMicro >= 0
            let sign = isPositive ? "+" : "-"
            return ("\(sign)\(VaultAmount.formatted(abs(vaultAmountMicro)))", isPositive)
        }

        let isPositive = trade.amount >= 0
        return ("\(isPositive ? "+" : "-")\(abs(trade.amount))", isPositive)
    }
}
