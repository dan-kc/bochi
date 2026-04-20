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
        self.trades = OwnerScopedRecordSupport.recordsForOwner(self.tradesByOwner, ownerID: initialOwnerID)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        trades = OwnerScopedRecordSupport.recordsForOwner(tradesByOwner, ownerID: ownerID)
    }

    func migrateTrades(from sourceOwnerID: String, to destinationOwnerID: String) -> [RecordID] {
        let migratedIDs = OwnerScopedRecordSupport.migrateRecords(
            from: sourceOwnerID,
            to: destinationOwnerID,
            recordsByOwner: &tradesByOwner
        )
        persist()
        refreshCurrentTrades()
        return migratedIDs
    }

    func addHabitTrade(
        id: RecordID? = nil,
        habitId: RecordID,
        amount: Int,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        let trade = Trade(
            id: id ?? RecordID(),
            habitId: habitId,
            rewardId: nil,
            amount: amount,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            deletedAt: deletedAt
        )

        appendOrReplace(trade, shouldNotifySync: shouldNotifySync)
    }

    func addRewardPurchase(
        id: RecordID? = nil,
        rewardId: RecordID,
        amount: Int,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        let trade = Trade(
            id: id ?? RecordID(),
            habitId: nil,
            rewardId: rewardId,
            amount: amount,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            deletedAt: deletedAt
        )

        appendOrReplace(trade, shouldNotifySync: shouldNotifySync)
    }

    func addHabitTradeWithDate(habitId: RecordID, amount: Int, createdAt: Date) {
        addHabitTrade(habitId: habitId, amount: amount, createdAt: createdAt)
    }

    func addRewardPurchaseWithDate(rewardId: RecordID, amount: Int, createdAt: Date) {
        addRewardPurchase(rewardId: rewardId, amount: amount, createdAt: createdAt)
    }

    // User behaviour: pricing for one habit should only respond to that habit's
    // own completion history, and deleted records should stop affecting the
    // visible reward immediately.
    func habitTradeDates(habitId: RecordID) -> [Date] {
        let canonicalHabitID = habitId
        return trades.compactMap { trade in
            guard trade.habitId == canonicalHabitID, trade.deletedAt == nil else { return nil }
            return trade.createdAt
        }
    }

    // User behaviour: each reward's price should react only to that reward's
    // own purchase history, not to other rewards or habit claims.
    func rewardPurchaseDates(rewardId: RecordID) -> [Date] {
        let canonicalRewardID = rewardId
        return trades.compactMap { trade in
            guard trade.rewardId == canonicalRewardID, trade.deletedAt == nil else { return nil }
            return trade.createdAt
        }
    }

    func tradesInPeriod(habitId: RecordID, days: Int) -> Int {
        let canonicalHabitID = habitId
        let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
        return trades.filter {
            $0.habitId == canonicalHabitID && $0.deletedAt == nil && $0.createdAt >= cutoff
        }.count
    }

    func rewardPurchasesInPeriod(rewardId: RecordID, days: Int) -> Int {
        let canonicalRewardID = rewardId
        let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
        return trades.filter {
            $0.rewardId == canonicalRewardID && $0.deletedAt == nil && $0.createdAt >= cutoff
        }.count
    }

    func mergeTrades(_ remoteTrades: [Trade]) {
        guard !remoteTrades.isEmpty else { return }
        mutateTrades {
            $0 = OwnerScopedRecordSupport.mergeRecords(local: $0, remote: remoteTrades)
        }
    }

    func replaceTrades(_ authoritativeTrades: [Trade]) {
        trades = OwnerScopedRecordSupport.sorted(authoritativeTrades)
        tradesByOwner[currentOwnerID] = trades
        persist()
    }

    func getDirtyTrades(ids: Set<RecordID>) -> [Trade] {
        trades.filter { ids.contains($0.id) }
    }

    func purgeDeletedTrades() {
        mutateTrades {
            $0.removeAll { $0.deletedAt != nil }
        }
    }

    func allTradeIDs() -> [RecordID] {
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
        trades = OwnerScopedRecordSupport.mutateRecords(
            currentRecords: trades,
            ownerID: currentOwnerID,
            recordsByOwner: &tradesByOwner,
            mutate: mutate
        )
        persist()
    }

    private func refreshCurrentTrades() {
        trades = OwnerScopedRecordSupport.recordsForOwner(tradesByOwner, ownerID: currentOwnerID)
    }

    private func persist() {
        JSONFileStore.save(PersistedState(tradesByOwner: tradesByOwner), to: storageURL)
    }

    private static func normalizePersistedTrades(_ tradesByOwner: [String: [Trade]]) -> [String: [Trade]] {
        OwnerScopedRecordSupport.normalizePersistedRecords(tradesByOwner) { trade in
            Trade(
                id: RecordID(rawValue: trade.id.rawValue),
                habitId: trade.habitId.map { RecordID(rawValue: $0.rawValue) },
                rewardId: trade.rewardId.map { RecordID(rawValue: $0.rawValue) },
                amount: trade.amount,
                createdAt: trade.createdAt,
                updatedAt: trade.updatedAt,
                deletedAt: trade.deletedAt
            )
        }
    }
}
