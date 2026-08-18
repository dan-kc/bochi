import Foundation

enum TradeKind: String, Codable, Sendable {
    case taskCompletion
    case recurringTaskCompletion
    case rewardPurchase
    case vaultDeposit
    case vaultInterest
    case vaultRewardPurchase

    var isVault: Bool {
        switch self {
        case .vaultDeposit, .vaultInterest, .vaultRewardPurchase:
            return true
        case .taskCompletion, .recurringTaskCompletion, .rewardPurchase:
            return false
        }
    }

    var isRefundable: Bool {
        switch self {
        case .taskCompletion, .recurringTaskCompletion, .rewardPurchase, .vaultRewardPurchase:
            return true
        case .vaultDeposit, .vaultInterest:
            return false
        }
    }
}

enum VaultAmount {
    static let microUnitsPerBochi = 1_000_000

    static func microUnits(forWholeBochi amount: Int) -> Int {
        amount * microUnitsPerBochi
    }

    static func wholeBochi(fromMicroUnits amount: Int) -> Int {
        amount / microUnitsPerBochi
    }

    static func formatted(_ microUnits: Int) -> String {
        let sign = microUnits < 0 ? "-" : ""
        let absoluteMicroUnits = abs(microUnits)
        let whole = absoluteMicroUnits / microUnitsPerBochi
        let fractional = absoluteMicroUnits % microUnitsPerBochi
        guard fractional > 0 else { return "\(sign)\(whole)" }

        var fractionText = String(format: "%06d", fractional)
        while fractionText.last == "0" {
            fractionText.removeLast()
        }
        return "\(sign)\(whole).\(fractionText)"
    }
}

// A trade record — represents either a recurringTask completion that earned points or a
// reward purchase that spent points.
// Like the RecurringTask struct, this is a value type (struct) — immutable, copied
// on assignment. Think of it like a frozen object in JS.
//
// Protocol conformances (like implementing interfaces in TS):
// - Identifiable: has an `id` property, used by SwiftUI List/ForEach for diffing
// - Equatable: supports `==` comparison (auto-synthesized for structs)
// - Sendable: safe to pass across threads
struct Trade: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let id: RecordID
    let taskId: RecordID?
    let recurringTaskId: RecordID?
    let rewardId: RecordID?
    let sourceName: String?
    let amount: Int
    let vaultAmountMicro: Int?
    let adjustmentBaseAmount: Int?
    let oneTimeAdjustmentMultiplier: Double?
    let tradeKind: TradeKind
    let vaultInterestHour: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let refundsTradeId: RecordID?
    let serverRevision: Int64?

    init(
        id: RecordID,
        taskId: RecordID?,
        recurringTaskId: RecordID?,
        rewardId: RecordID?,
        sourceName: String? = nil,
        amount: Int,
        vaultAmountMicro: Int? = nil,
        adjustmentBaseAmount: Int? = nil,
        oneTimeAdjustmentMultiplier: Double? = nil,
        tradeKind: TradeKind? = nil,
        vaultInterestHour: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        refundsTradeId: RecordID? = nil,
        serverRevision: Int64? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.recurringTaskId = recurringTaskId
        self.rewardId = rewardId
        self.sourceName = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? sourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        self.amount = amount
        let resolvedTradeKind = tradeKind ?? Self.defaultKind(taskId: taskId, recurringTaskId: recurringTaskId, rewardId: rewardId)
        self.vaultAmountMicro = vaultAmountMicro ?? Self.defaultVaultAmountMicro(
            amount: amount,
            tradeKind: resolvedTradeKind
        )
        self.adjustmentBaseAmount = adjustmentBaseAmount
        self.oneTimeAdjustmentMultiplier = oneTimeAdjustmentMultiplier
        self.tradeKind = resolvedTradeKind
        self.vaultInterestHour = vaultInterestHour
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.refundsTradeId = refundsTradeId
        self.serverRevision = serverRevision
    }

    var isRefundTrade: Bool {
        refundsTradeId != nil
    }

    var isRefunded: Bool {
        isRefundTrade
    }

    static func defaultKind(taskId: RecordID?, recurringTaskId: RecordID?, rewardId: RecordID?) -> TradeKind {
        if taskId != nil { return .taskCompletion }
        if recurringTaskId != nil { return .recurringTaskCompletion }
        if rewardId != nil { return .rewardPurchase }
        return .vaultDeposit
    }

    private static func defaultVaultAmountMicro(amount: Int, tradeKind: TradeKind) -> Int? {
        switch tradeKind {
        case .vaultDeposit:
            return VaultAmount.microUnits(forWholeBochi: -amount)
        case .vaultInterest, .vaultRewardPurchase:
            return VaultAmount.microUnits(forWholeBochi: amount)
        case .taskCompletion, .recurringTaskCompletion, .rewardPurchase:
            return nil
        }
    }
}
