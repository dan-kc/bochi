import Foundation

@Observable
@MainActor
final class TradeStore {
    private struct PersistedState: Codable {
        var tradesByOwner: [String: [Trade]] = [:]
    }

    private let storageURL: URL
    private(set) var currentOwnerID: String
    private var tradesByOwner: [String: [Trade]]

    private(set) var trades: [Trade] = []

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.storageURL = storageURL ?? AppStorageLocation.fileURL(filename: "trades")
        self.currentOwnerID = initialOwnerID
        let persisted = JSONFileStore.load(PersistedState.self, from: self.storageURL, defaultValue: PersistedState())
        self.tradesByOwner = Self.normalizePersistedTrades(persisted.tradesByOwner)
        self.trades = self.tradesByOwner[initialOwnerID] ?? []
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        trades = tradesByOwner[ownerID] ?? []
    }

    func migrateTrades(from sourceOwnerID: String, to destinationOwnerID: String) -> [String] {
        guard sourceOwnerID != destinationOwnerID else { return [] }

        let source = tradesByOwner[sourceOwnerID] ?? []
        let destination = tradesByOwner[destinationOwnerID] ?? []
        let merged = mergeRecords(local: destination, remote: source)
        let migratedIDs = source.map(\.id)

        tradesByOwner[destinationOwnerID] = merged
        tradesByOwner[sourceOwnerID] = []
        persist()
        refreshCurrentTrades()
        return migratedIDs
    }

    func addHabitTrade(
        id: String? = nil,
        habitId: String,
        amount: Int,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        let trade = Trade(
            id: CanonicalRecordID.normalize(id ?? UUID().uuidString),
            habitId: CanonicalRecordID.normalize(habitId),
            rewardId: nil,
            amount: amount,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            deletedAt: deletedAt
        )

        appendOrReplace(trade, shouldNotifySync: shouldNotifySync)
    }

    func addRewardPurchase(
        id: String? = nil,
        rewardId: String,
        amount: Int,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        let trade = Trade(
            id: CanonicalRecordID.normalize(id ?? UUID().uuidString),
            habitId: nil,
            rewardId: CanonicalRecordID.normalize(rewardId),
            amount: amount,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            deletedAt: deletedAt
        )

        appendOrReplace(trade, shouldNotifySync: shouldNotifySync)
    }

    func addHabitTradeWithDate(habitId: String, amount: Int, createdAt: Date) {
        addHabitTrade(habitId: habitId, amount: amount, createdAt: createdAt)
    }

    func addRewardPurchaseWithDate(rewardId: String, amount: Int, createdAt: Date) {
        addRewardPurchase(rewardId: rewardId, amount: amount, createdAt: createdAt)
    }

    // User behaviour: pricing for one habit should only respond to that habit's
    // own completion history, and deleted records should stop affecting the
    // visible reward immediately.
    func habitTradeDates(habitId: String) -> [Date] {
        let canonicalHabitID = CanonicalRecordID.normalize(habitId)
        return trades.compactMap { trade in
            guard trade.habitId == canonicalHabitID, trade.deletedAt == nil else { return nil }
            return trade.createdAt
        }
    }

    // User behaviour: each reward's price should react only to that reward's
    // own purchase history, not to other rewards or habit claims.
    func rewardPurchaseDates(rewardId: String) -> [Date] {
        let canonicalRewardID = CanonicalRecordID.normalize(rewardId)
        return trades.compactMap { trade in
            guard trade.rewardId == canonicalRewardID, trade.deletedAt == nil else { return nil }
            return trade.createdAt
        }
    }

    func tradesInPeriod(habitId: String, days: Int) -> Int {
        let canonicalHabitID = CanonicalRecordID.normalize(habitId)
        let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
        return trades.filter {
            $0.habitId == canonicalHabitID && $0.deletedAt == nil && $0.createdAt >= cutoff
        }.count
    }

    func rewardPurchasesInPeriod(rewardId: String, days: Int) -> Int {
        let canonicalRewardID = CanonicalRecordID.normalize(rewardId)
        let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
        return trades.filter {
            $0.rewardId == canonicalRewardID && $0.deletedAt == nil && $0.createdAt >= cutoff
        }.count
    }

    func mergeTrades(_ remoteTrades: [Trade]) {
        guard !remoteTrades.isEmpty else { return }
        mutateTrades {
            $0 = mergeRecords(local: $0, remote: remoteTrades)
        }
    }

    func getDirtyTrades(ids: Set<String>) -> [Trade] {
        trades.filter { ids.contains($0.id) }
    }

    func purgeDeletedTrades() {
        mutateTrades {
            $0.removeAll { $0.deletedAt != nil }
        }
    }

    func allTradeIDs() -> [String] {
        trades.map(\.id)
    }

    private func appendOrReplace(_ trade: Trade, shouldNotifySync: Bool) {
        mutateTrades {
            $0.removeAll { $0.id == trade.id }
            $0.append(trade)
        }

        if shouldNotifySync {
            SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .trades, recordIDs: [trade.id]))
        }
    }

    private func mutateTrades(_ mutate: (inout [Trade]) -> Void) {
        var next = trades
        mutate(&next)
        next.sort { $0.createdAt < $1.createdAt }
        trades = next
        tradesByOwner[currentOwnerID] = next
        persist()
    }

    private func refreshCurrentTrades() {
        trades = tradesByOwner[currentOwnerID] ?? []
    }

    private func persist() {
        JSONFileStore.save(PersistedState(tradesByOwner: tradesByOwner), to: storageURL)
    }

    private func mergeRecords(local: [Trade], remote: [Trade]) -> [Trade] {
        var mergedByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

        for incoming in remote {
            if let existing = mergedByID[incoming.id], existing.updatedAt > incoming.updatedAt {
                continue
            }
            mergedByID[incoming.id] = incoming
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private static func normalizePersistedTrades(_ tradesByOwner: [String: [Trade]]) -> [String: [Trade]] {
        Dictionary(uniqueKeysWithValues: tradesByOwner.map { ownerID, trades in
            (ownerID, normalizeTrades(trades))
        })
    }

    private static func normalizeTrades(_ trades: [Trade]) -> [Trade] {
        var newestByID: [String: Trade] = [:]

        for trade in trades {
            let normalized = Trade(
                id: CanonicalRecordID.normalize(trade.id),
                habitId: CanonicalRecordID.normalize(trade.habitId),
                rewardId: CanonicalRecordID.normalize(trade.rewardId),
                amount: trade.amount,
                createdAt: trade.createdAt,
                updatedAt: trade.updatedAt,
                deletedAt: trade.deletedAt
            )

            if let existing = newestByID[normalized.id], existing.updatedAt > normalized.updatedAt {
                continue
            }

            newestByID[normalized.id] = normalized
        }

        return newestByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
