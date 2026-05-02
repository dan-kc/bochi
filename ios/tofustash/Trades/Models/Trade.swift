import Foundation

// A trade record — represents either a habit completion that earned tofu or a
// reward purchase that spent tofu.
// Like the Habit struct, this is a value type (struct) — immutable, copied
// on assignment. Think of it like a frozen object in JS.
//
// Protocol conformances (like implementing interfaces in TS):
// - Identifiable: has an `id` property, used by SwiftUI List/ForEach for diffing
// - Equatable: supports `==` comparison (auto-synthesized for structs)
// - Sendable: safe to pass across threads
struct Trade: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let id: RecordID
    let taskId: RecordID?
    let habitId: RecordID?
    let rewardId: RecordID?
    let sourceName: String?
    let amount: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let refundsTradeId: RecordID?

    init(
        id: RecordID,
        taskId: RecordID?,
        habitId: RecordID?,
        rewardId: RecordID?,
        sourceName: String? = nil,
        amount: Int,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        refundsTradeId: RecordID? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.habitId = habitId
        self.rewardId = rewardId
        self.sourceName = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? sourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        self.amount = amount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.refundsTradeId = refundsTradeId
    }

    var isRefundTrade: Bool {
        refundsTradeId != nil
    }

    var isRefunded: Bool {
        isRefundTrade
    }
}
