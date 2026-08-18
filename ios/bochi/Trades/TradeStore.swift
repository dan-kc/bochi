import Foundation
import GRDB

// Sync flow: completions, purchases, refunds, and vault interest create trade
// rows; signed-in trade changes become dirty records for the next push.
@Observable
@MainActor
final class TradeStore {
    nonisolated static let hourlyVaultInterestRate = pow(1.08, 1.0 / (30.0 * 24.0)) - 1.0

    private struct TradeProjection {
        var recurringTaskTradeDatesByRecurringTaskID: [RecordID: [Date]] = [:]
        var recurringTaskCompletionCountsByRecurringTaskID: [RecordID: Int] = [:]
        var rewardPurchaseDatesByRewardID: [RecordID: [Date]] = [:]
        var latestUnrefundedTaskTradesByTaskID: [RecordID: Trade] = [:]
        var latestUnrefundedRewardPurchasesByRewardID: [RecordID: Trade] = [:]
        var activeRefundedTradeIDs: Set<RecordID> = []

        init(trades: [Trade]) {
            activeRefundedTradeIDs = Set(
                trades
                    .filter { $0.deletedAt == nil }
                    .compactMap(\.refundsTradeId)
            )

            for trade in trades {
                guard trade.deletedAt == nil, !trade.isRefundTrade, !activeRefundedTradeIDs.contains(trade.id) else {
                    continue
                }

                if let recurringTaskId = trade.recurringTaskId {
                    recurringTaskTradeDatesByRecurringTaskID[recurringTaskId, default: []].append(trade.createdAt)
                    recurringTaskCompletionCountsByRecurringTaskID[recurringTaskId, default: 0] += 1
                }

                if let rewardId = trade.rewardId {
                    rewardPurchaseDatesByRewardID[rewardId, default: []].append(trade.createdAt)
                    if let existing = latestUnrefundedRewardPurchasesByRewardID[rewardId] {
                        if Self.isNewerLatestTradeCandidate(trade, than: existing) {
                            latestUnrefundedRewardPurchasesByRewardID[rewardId] = trade
                        }
                    } else {
                        latestUnrefundedRewardPurchasesByRewardID[rewardId] = trade
                    }
                }

                if let taskId = trade.taskId {
                    guard let existing = latestUnrefundedTaskTradesByTaskID[taskId] else {
                        latestUnrefundedTaskTradesByTaskID[taskId] = trade
                        continue
                    }
                    if Self.isNewerLatestTradeCandidate(trade, than: existing) {
                        latestUnrefundedTaskTradesByTaskID[taskId] = trade
                    }
                }
            }
        }

        private static func isNewerLatestTradeCandidate(_ candidate: Trade, than existing: Trade) -> Bool {
            if candidate.createdAt == existing.createdAt {
                if candidate.updatedAt == existing.updatedAt {
                    return candidate.id.rawValue > existing.id.rawValue
                }
                return candidate.updatedAt > existing.updatedAt
            }
            return candidate.createdAt > existing.createdAt
        }
    }

    private enum TradeSource {
        case task(RecordID, String?)
        case recurringTask(RecordID, String?)
        case reward(RecordID, String?)
        case vaultDeposit(String?)
        case vaultInterest(String?, Date)
        case vaultReward(RecordID, String?)
    }

    private struct TradeEntry {
        let id: RecordID
        let amount: Int
        let vaultAmountMicro: Int?
        let adjustmentBaseAmount: Int?

        init(
            id: RecordID,
            amount: Int,
            vaultAmountMicro: Int? = nil,
            adjustmentBaseAmount: Int? = nil
        ) {
            self.id = id
            self.amount = amount
            self.vaultAmountMicro = vaultAmountMicro
            self.adjustmentBaseAmount = adjustmentBaseAmount
        }
    }

    private let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore

    private(set) var currentOwnerID: String
    private(set) var trades: [Trade] = [] {
        didSet {
            // List pricing, lockout, and dependency checks all need the same
            // trade summaries; rebuild them once when the ledger changes.
            tradeProjection = TradeProjection(trades: trades)
        }
    }
    private var tradeProjection = TradeProjection(trades: [])

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device",
        accruesVaultInterestOnLoad: Bool = true,
        vaultInterestAccrualNow: Date = Date()
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.syncStateStore = SyncStateStore(storageURL: self.databaseURL)
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        self.trades = loadTrades(ownerID: initialOwnerID)
        self.tradeProjection = TradeProjection(trades: self.trades)
        try? recalculateBalance(ownerID: initialOwnerID)
        if accruesVaultInterestOnLoad {
            // Behaviour: returning to the app should materialize missed vault
            // interest before any tab-specific view, including Vault, appears.
            accrueVaultInterestIfNeeded(now: vaultInterestAccrualNow)
        }
    }

    func setCurrentOwner(_ ownerID: String, vaultInterestAccrualNow: Date = Date()) {
        currentOwnerID = ownerID
        trades = loadTrades(ownerID: ownerID)
        try? recalculateBalance(ownerID: ownerID)
        // Behaviour: signed-in account trades load after auth bootstrap, so
        // vault interest must accrue when the owner ledger switches too.
        accrueVaultInterestIfNeeded(now: vaultInterestAccrualNow)
    }

    func migrateTrades(from sourceOwnerID: String, to destinationOwnerID: String) -> [RecordID] {
        guard sourceOwnerID != destinationOwnerID else { return [] }
        do {
            let migratedIDs = try database.transaction(at: databaseURL) { db in
                try self.migrateTrades(from: sourceOwnerID, to: destinationOwnerID, on: db)
            }
            refreshCurrentTrades()
            return migratedIDs
        } catch {
            assertionFailure("Failed to migrate trades: \(error)")
            return []
        }
    }

    func addRecurringTaskTrade(
        id: RecordID? = nil,
        recurringTaskId: RecordID,
        sourceName: String? = nil,
        amount: Int,
        adjustmentBaseAmount: Int? = nil,
        oneTimeAdjustmentMultiplier: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        addRecurringTaskTrades(
            entries: [(id: id ?? RecordID(), amount: amount, adjustmentBaseAmount: adjustmentBaseAmount)],
            recurringTaskId: recurringTaskId,
            sourceName: sourceName,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func addTaskTrade(
        id: RecordID? = nil,
        taskId: RecordID,
        sourceName: String? = nil,
        amount: Int,
        adjustmentBaseAmount: Int? = nil,
        oneTimeAdjustmentMultiplier: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        addTaskTrades(
            entries: [(id: id ?? RecordID(), amount: amount, adjustmentBaseAmount: adjustmentBaseAmount)],
            taskId: taskId,
            sourceName: sourceName,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func addRewardPurchase(
        id: RecordID? = nil,
        rewardId: RecordID,
        sourceName: String? = nil,
        amount: Int,
        adjustmentBaseAmount: Int? = nil,
        oneTimeAdjustmentMultiplier: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        addRewardPurchases(
            entries: [(id: id ?? RecordID(), amount: amount, adjustmentBaseAmount: adjustmentBaseAmount)],
            rewardId: rewardId,
            sourceName: sourceName,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func addVaultDeposit(
        id: RecordID? = nil,
        amount: Int,
        createdAt: Date = Date(),
        shouldNotifySync: Bool = true
    ) {
        guard amount > 0 else { return }
        addTrades(
            entries: [
                TradeEntry(
                    id: id ?? RecordID(),
                    amount: -amount,
                    vaultAmountMicro: VaultAmount.microUnits(forWholeBochi: amount)
                )
            ],
            source: .vaultDeposit("Bank deposit"),
            oneTimeAdjustmentMultiplier: nil,
            createdAt: createdAt,
            updatedAt: nil,
            deletedAt: nil,
            shouldNotifySync: shouldNotifySync
        )
    }

    func addVaultInterest(
        id: RecordID? = nil,
        vaultAmountMicro: Int,
        vaultInterestHour: Date,
        createdAt: Date,
        shouldNotifySync: Bool = true
    ) {
        guard vaultAmountMicro > 0 else { return }
        addTrades(
            entries: [
                TradeEntry(
                    id: id ?? RecordID(),
                    amount: 0,
                    vaultAmountMicro: vaultAmountMicro
                )
            ],
            source: .vaultInterest("Bank interest", vaultInterestHour),
            oneTimeAdjustmentMultiplier: nil,
            createdAt: createdAt,
            updatedAt: nil,
            deletedAt: nil,
            shouldNotifySync: shouldNotifySync
        )
    }

    func addVaultRewardPurchases(
        entries: [(id: RecordID, amount: Int, adjustmentBaseAmount: Int?)],
        rewardId: RecordID,
        sourceName: String? = nil,
        oneTimeAdjustmentMultiplier: Double? = nil,
        createdAt: Date = Date(),
        shouldNotifySync: Bool = true
    ) {
        addTrades(
            entries: entries.map { entry in
                TradeEntry(
                    id: entry.id,
                    amount: 0,
                    vaultAmountMicro: VaultAmount.microUnits(forWholeBochi: entry.amount),
                    adjustmentBaseAmount: entry.adjustmentBaseAmount
                )
            },
            source: .vaultReward(rewardId, sourceName),
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            createdAt: createdAt,
            updatedAt: nil,
            deletedAt: nil,
            shouldNotifySync: shouldNotifySync
        )
    }

    func addRecurringTaskTrades(
        entries: [(id: RecordID, amount: Int, adjustmentBaseAmount: Int?)],
        recurringTaskId: RecordID,
        sourceName: String? = nil,
        oneTimeAdjustmentMultiplier: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        addTrades(
            entries: entries.map { entry in
                TradeEntry(
                    id: entry.id,
                    amount: entry.amount,
                    adjustmentBaseAmount: entry.adjustmentBaseAmount
                )
            },
            source: .recurringTask(recurringTaskId, sourceName),
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func addTaskTrades(
        entries: [(id: RecordID, amount: Int, adjustmentBaseAmount: Int?)],
        taskId: RecordID,
        sourceName: String? = nil,
        oneTimeAdjustmentMultiplier: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        addTrades(
            entries: entries.map { entry in
                TradeEntry(
                    id: entry.id,
                    amount: entry.amount,
                    adjustmentBaseAmount: entry.adjustmentBaseAmount
                )
            },
            source: .task(taskId, sourceName),
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func addRewardPurchases(
        entries: [(id: RecordID, amount: Int, adjustmentBaseAmount: Int?)],
        rewardId: RecordID,
        sourceName: String? = nil,
        oneTimeAdjustmentMultiplier: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        addTrades(
            entries: entries.map { entry in
                TradeEntry(
                    id: entry.id,
                    amount: entry.amount,
                    adjustmentBaseAmount: entry.adjustmentBaseAmount
                )
            },
            source: .reward(rewardId, sourceName),
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func addRecurringTaskTradeWithDate(recurringTaskId: RecordID, amount: Int, createdAt: Date) {
        addRecurringTaskTrade(recurringTaskId: recurringTaskId, amount: amount, createdAt: createdAt)
    }

    func addTaskTradeWithDate(taskId: RecordID, amount: Int, createdAt: Date) {
        addTaskTrade(taskId: taskId, amount: amount, createdAt: createdAt)
    }

    func addRewardPurchaseWithDate(rewardId: RecordID, amount: Int, createdAt: Date) {
        addRewardPurchase(rewardId: rewardId, amount: amount, createdAt: createdAt)
    }

    func recurringTaskTradeDates(recurringTaskId: RecordID) -> [Date] {
        trades.compactMap { trade in
            guard trade.recurringTaskId == recurringTaskId, isUnresolvedSourceTrade(trade) else { return nil }
            return trade.createdAt
        }
    }

    func recurringTaskTradeDatesByRecurringTaskID() -> [RecordID: [Date]] {
        tradeProjection.recurringTaskTradeDatesByRecurringTaskID
    }

    func recurringTaskCompletionCount(recurringTaskId: RecordID) -> Int {
        trades.reduce(into: 0) { count, trade in
            guard trade.recurringTaskId == recurringTaskId, isUnresolvedSourceTrade(trade) else { return }
            count += 1
        }
    }

    func recurringTaskCompletionCountsByRecurringTaskID() -> [RecordID: Int] {
        tradeProjection.recurringTaskCompletionCountsByRecurringTaskID
    }

    func rewardPurchaseDates(rewardId: RecordID) -> [Date] {
        trades.compactMap { trade in
            guard trade.rewardId == rewardId, isUnresolvedSourceTrade(trade) else { return nil }
            return trade.createdAt
        }
    }

    func rewardPurchaseDatesByRewardID() -> [RecordID: [Date]] {
        tradeProjection.rewardPurchaseDatesByRewardID
    }

    func tradesInPeriod(recurringTaskId: RecordID, days: Int) -> Int {
        let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
        return trades.filter {
            $0.recurringTaskId == recurringTaskId && isUnresolvedSourceTrade($0) && $0.createdAt >= cutoff
        }.count
    }

    func rewardPurchasesInPeriod(rewardId: RecordID, days: Int) -> Int {
        let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
        return trades.filter {
            $0.rewardId == rewardId && isUnresolvedSourceTrade($0) && $0.createdAt >= cutoff
        }.count
    }

    func vaultBalance() -> Int {
        VaultAmount.wholeBochi(fromMicroUnits: vaultBalanceMicro())
    }

    func vaultBalanceMicro() -> Int {
        vaultBalanceMicro(before: nil)
    }

    func vaultInterestEarned(since cutoff: Date, now: Date = Date()) -> Int {
        VaultAmount.wholeBochi(fromMicroUnits: vaultInterestEarnedMicro(since: cutoff, now: now))
    }

    func vaultInterestEarnedMicro(since cutoff: Date, now: Date = Date()) -> Int {
        trades.reduce(into: 0) { total, trade in
            guard trade.deletedAt == nil,
                  trade.tradeKind == .vaultInterest,
                  trade.createdAt >= cutoff,
                  trade.createdAt <= now else { return }
            total += trade.vaultAmountMicro ?? 0
        }
    }

    func nextVaultPurchaseAvailableAt(now: Date = Date()) -> Date? {
        guard let latestSpend = latestVaultRewardPurchase(includeRefunded: false) else { return nil }
        let availableAt = latestSpend.createdAt.addingTimeInterval(30 * 24 * 60 * 60)
        return availableAt > now ? availableAt : nil
    }

    func accrueVaultInterestIfNeeded(now: Date = Date(), shouldNotifySync: Bool = true) {
        let calendar = Calendar.utcVaultCalendar
        let lastCompletedHour = calendar.startOfHour(for: now)
        guard let firstVaultTradeDate = trades
            .filter({ $0.deletedAt == nil && $0.tradeKind.isVault })
            .map(\.createdAt)
            .min()
        else { return }

        var hour = calendar.nextHourStart(after: firstVaultTradeDate)
        while hour <= lastCompletedHour {
            if !hasVaultInterest(for: hour) {
                let balanceAtHourStart = vaultBalanceMicro(before: hour)
                let interest = Int(floor(Double(balanceAtHourStart) * Self.hourlyVaultInterestRate))
                if interest > 0 {
                    addVaultInterest(
                        vaultAmountMicro: interest,
                        vaultInterestHour: hour,
                        createdAt: hour,
                        shouldNotifySync: shouldNotifySync
                    )
                }
            }
            guard let nextHour = calendar.date(byAdding: .hour, value: 1, to: hour) else { break }
            hour = nextHour
        }
    }

    func latestTaskTrade(taskId: RecordID, includeRefunded: Bool = true) -> Trade? {
        latestTrade(includeRefunded: includeRefunded) { trade in
            trade.taskId == taskId && trade.deletedAt == nil
        }
    }

    func latestRewardPurchase(rewardId: RecordID, includeRefunded: Bool = true) -> Trade? {
        latestTrade(includeRefunded: includeRefunded) { trade in
            trade.rewardId == rewardId && trade.deletedAt == nil
        }
    }

    func latestVaultRewardPurchase(includeRefunded: Bool = false) -> Trade? {
        latestTrade(includeRefunded: includeRefunded) { trade in
            trade.tradeKind == .vaultRewardPurchase && trade.deletedAt == nil
        }
    }

    func latestUnrefundedTaskTradesByTaskID() -> [RecordID: Trade] {
        tradeProjection.latestUnrefundedTaskTradesByTaskID
    }

    func latestUnrefundedRewardPurchasesByRewardID() -> [RecordID: Trade] {
        tradeProjection.latestUnrefundedRewardPurchasesByRewardID
    }

    func activeTaskTradeCompletionDate(taskId: RecordID) -> Date? {
        latestTaskTrade(taskId: taskId, includeRefunded: false)?.createdAt
    }

    func canRefundTrade(_ trade: Trade) -> Bool {
        guard trade.deletedAt == nil, !trade.isRefundTrade, trade.tradeKind.isRefundable else { return false }

        return latestTrade(includeRefunded: false) { candidate in
            candidate.taskId == trade.taskId
                && candidate.recurringTaskId == trade.recurringTaskId
                && candidate.rewardId == trade.rewardId
                && candidate.tradeKind == trade.tradeKind
                && candidate.deletedAt == nil
        }?.id == trade.id
    }

    @discardableResult
    func refundTrade(
        id: RecordID,
        refundedAt: Date = Date(),
        shouldNotifySync: Bool = true
    ) -> Trade? {
        guard let existing = trades.first(where: { $0.id == id }) else {
            return nil
        }
        guard canRefundTrade(existing) else {
            return nil
        }
        guard refundedAt >= existing.createdAt else {
            return nil
        }

        let refundTrade = Trade(
            id: RecordID(),
            taskId: existing.taskId,
            recurringTaskId: existing.recurringTaskId,
            rewardId: existing.rewardId,
            sourceName: existing.sourceName,
            amount: -existing.amount,
            vaultAmountMicro: existing.vaultAmountMicro.map { -$0 },
            adjustmentBaseAmount: existing.adjustmentBaseAmount.map { -$0 },
            oneTimeAdjustmentMultiplier: existing.oneTimeAdjustmentMultiplier,
            tradeKind: existing.tradeKind,
            createdAt: refundedAt,
            updatedAt: refundedAt,
            deletedAt: nil,
            refundsTradeId: existing.id
        )

        upsertTrades([refundTrade], markDirty: shouldNotifySync)

        if shouldNotifySync {
            notifySync(ids: [refundTrade.id])
        }

        return refundTrade
    }

    func mergeTrades(_ remoteTrades: [Trade]) {
        guard !remoteTrades.isEmpty else { return }
        replaceTrades(OwnerScopedRecordSupport.mergeRecords(local: trades, remote: remoteTrades))
    }

    func replaceTrades(_ authoritativeTrades: [Trade]) {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeTrades)
        do {
            try persistReplacedTrades(sorted)
        } catch {
            assertionFailure("Failed to replace trades: \(error)")
            return
        }
    }

    func getDirtyTrades(ids: Set<RecordID>) -> [Trade] {
        trades.filter { ids.contains($0.id) }
    }

    func purgeDeletedTrades(excluding dirtyIDs: Set<RecordID> = []) {
        do {
            try persistDeletedTradePurge(excluding: dirtyIDs)
        } catch {
            assertionFailure("Failed to purge deleted trades: \(error)")
            return
        }
    }

    func allTradeIDs() -> [RecordID] {
        trades.map(\.id)
    }

    func historyTrades(filter: TradeHistoryFilter = .all) -> [Trade] {
        // Opening history for one task, recurring task, or reward should read only that
        // source's rows instead of sorting the entire in-memory ledger.
        var sql = """
            SELECT id, task_id, recurring_task_id, reward_id, source_name, amount, vault_amount_micro, adjustment_base_amount, one_time_adjustment_multiplier, trade_kind, vault_interest_hour, created_at, updated_at, deleted_at, refunds_trade_id, server_revision
            FROM trades
            WHERE owner_id = ? AND deleted_at IS NULL AND trade_kind != ?
            """
        var bindings: [SQLiteValue] = [.text(currentOwnerID), .text(TradeKind.vaultInterest.rawValue)]

        switch filter {
        case .all:
            break
        case .task(let taskID):
            sql += " AND task_id = ?"
            bindings.append(.text(taskID.rawValue))
        case .recurringTask(let recurringTaskID):
            sql += " AND recurring_task_id = ?"
            bindings.append(.text(recurringTaskID.rawValue))
        case .reward(let rewardID):
            sql += " AND reward_id = ?"
            bindings.append(.text(rewardID.rawValue))
        }

        sql += " ORDER BY created_at DESC, id DESC"

        return (try? database.query(
            sql,
            bindings: bindings,
            at: databaseURL,
            map: Self.trade(from:)
        )) ?? []
    }

    func migrateTrades(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> [RecordID] {
        guard sourceOwnerID != destinationOwnerID else { return [] }
        let source = loadTrades(ownerID: sourceOwnerID)
        let destination = loadTrades(ownerID: destinationOwnerID)
        let migration = makeTradeOwnerMigration(source: source, destination: destination)

        // Remove the local-owner rows before re-inserting the merged account view
        // so a sign-in migration does not trip the global trade-id uniqueness rule.
        try replaceRows(ownerID: sourceOwnerID, trades: [], on: databaseHandle)
        try replaceRows(ownerID: destinationOwnerID, trades: migration.mergedTrades, on: databaseHandle)
        try recalculateBalance(ownerID: destinationOwnerID, on: databaseHandle)
        try recalculateBalance(ownerID: sourceOwnerID, on: databaseHandle)
        return migration.migratedTradeIDs
    }

    func persistReplacedTrades(_ authoritativeTrades: [Trade]) throws {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeTrades)
        try database.transaction(at: databaseURL) { db in
            try self.replaceRows(ownerID: self.currentOwnerID, trades: sorted, on: db)
            try self.recalculateBalance(ownerID: self.currentOwnerID, on: db)
        }
        trades = sorted
    }

    func replaceTrades(
        _ authoritativeTrades: [Trade],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeTrades)
        try replaceRows(ownerID: currentOwnerID, trades: sorted, on: databaseHandle)
        try recalculateBalance(ownerID: currentOwnerID, on: databaseHandle)
    }

    private func latestTrade(
        includeRefunded: Bool,
        where predicate: (Trade) -> Bool
    ) -> Trade? {
        let refundedTradeIDs = includeRefunded ? [] : tradeProjection.activeRefundedTradeIDs
        var latest: Trade?

        for trade in trades {
            guard trade.deletedAt == nil, predicate(trade) else { continue }
            if !includeRefunded {
                guard !trade.isRefundTrade, !refundedTradeIDs.contains(trade.id) else { continue }
            }

            guard let existing = latest else {
                latest = trade
                continue
            }

            if isNewerLatestTradeCandidate(trade, than: existing) {
                latest = trade
            }
        }

        return latest
    }

    private func isNewerLatestTradeCandidate(_ candidate: Trade, than existing: Trade) -> Bool {
        if candidate.createdAt == existing.createdAt {
            if candidate.updatedAt == existing.updatedAt {
                return candidate.id.rawValue > existing.id.rawValue
            }
            return candidate.updatedAt > existing.updatedAt
        }
        return candidate.createdAt > existing.createdAt
    }

    private func addTrades(
        entries: [TradeEntry],
        source: TradeSource,
        oneTimeAdjustmentMultiplier: Double?,
        createdAt: Date,
        updatedAt: Date?,
        deletedAt: Date?,
        shouldNotifySync: Bool
    ) {
        guard !entries.isEmpty else { return }

        let rows = makeTrades(
            entries: entries,
            source: source,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )

        upsertTrades(rows, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(ids: rows.map(\.id))
        }
    }

    func persistDeletedTradePurge(excluding dirtyIDs: Set<RecordID>) throws {
        try database.transaction(at: databaseURL) { db in
            try self.purgeDeletedTrades(excluding: dirtyIDs, on: db)
        }
        refreshCurrentTrades()
    }

    func purgeDeletedTrades(
        excluding dirtyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        if dirtyIDs.isEmpty {
            try database.execute(
                "DELETE FROM trades WHERE owner_id = ? AND deleted_at IS NOT NULL",
                bindings: [.text(currentOwnerID)],
                on: databaseHandle
            )
        } else {
            let placeholders = Array(repeating: "?", count: dirtyIDs.count).joined(separator: ", ")
            let bindings: [SQLiteValue] = [SQLiteValue.text(currentOwnerID)]
                + dirtyIDs.sorted { $0.rawValue < $1.rawValue }.map { SQLiteValue.text($0.rawValue) }
            try database.execute(
                "DELETE FROM trades WHERE owner_id = ? AND deleted_at IS NOT NULL AND id NOT IN (\(placeholders))",
                bindings: bindings,
                on: databaseHandle
            )
        }

        try recalculateBalance(ownerID: currentOwnerID, on: databaseHandle)
    }

    private func upsertTrades(_ newTrades: [Trade], markDirty: Bool) {
        guard !newTrades.isEmpty else { return }

        do {
            try database.transaction(at: databaseURL) { db in
                for trade in newTrades {
                    try self.upsertTrade(trade, on: db)
                }
                if markDirty, self.currentOwnerID != StorageOwner.local {
                    try self.syncStateStore.markDirty(
                        userID: self.currentOwnerID,
                        kind: .trades,
                        ids: newTrades.map(\.id),
                        on: db
                    )
                }
                try self.recalculateBalance(ownerID: self.currentOwnerID, on: db)
            }
        } catch {
            assertionFailure("Failed to upsert trades: \(error)")
            return
        }

        refreshCurrentTrades()
    }

    private func makeTrades(
        entries: [TradeEntry],
        source: TradeSource,
        oneTimeAdjustmentMultiplier: Double?,
        createdAt: Date,
        updatedAt: Date?,
        deletedAt: Date?
    ) -> [Trade] {
        entries.map { entry in
            switch source {
            case .task(let taskId, let sourceName):
                return Trade(
                    id: entry.id,
                    taskId: taskId,
                    recurringTaskId: nil,
                    rewardId: nil,
                    sourceName: sourceName,
                    amount: entry.amount,
                    vaultAmountMicro: nil,
                    adjustmentBaseAmount: entry.adjustmentBaseAmount,
                    oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                    createdAt: createdAt,
                    updatedAt: updatedAt ?? createdAt,
                    deletedAt: deletedAt
                )
            case .recurringTask(let recurringTaskId, let sourceName):
                return Trade(
                    id: entry.id,
                    taskId: nil,
                    recurringTaskId: recurringTaskId,
                    rewardId: nil,
                    sourceName: sourceName,
                    amount: entry.amount,
                    vaultAmountMicro: nil,
                    adjustmentBaseAmount: entry.adjustmentBaseAmount,
                    oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                    createdAt: createdAt,
                    updatedAt: updatedAt ?? createdAt,
                    deletedAt: deletedAt
                )
            case .reward(let rewardId, let sourceName):
                return Trade(
                    id: entry.id,
                    taskId: nil,
                    recurringTaskId: nil,
                    rewardId: rewardId,
                    sourceName: sourceName,
                    amount: entry.amount,
                    vaultAmountMicro: nil,
                    adjustmentBaseAmount: entry.adjustmentBaseAmount,
                    oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                    createdAt: createdAt,
                    updatedAt: updatedAt ?? createdAt,
                    deletedAt: deletedAt
                )
            case .vaultDeposit(let sourceName):
                return Trade(
                    id: entry.id,
                    taskId: nil,
                    recurringTaskId: nil,
                    rewardId: nil,
                    sourceName: sourceName,
                    amount: entry.amount,
                    vaultAmountMicro: entry.vaultAmountMicro,
                    adjustmentBaseAmount: nil,
                    oneTimeAdjustmentMultiplier: nil,
                    tradeKind: .vaultDeposit,
                    createdAt: createdAt,
                    updatedAt: updatedAt ?? createdAt,
                    deletedAt: deletedAt
                )
            case .vaultInterest(let sourceName, let vaultInterestHour):
                return Trade(
                    id: entry.id,
                    taskId: nil,
                    recurringTaskId: nil,
                    rewardId: nil,
                    sourceName: sourceName,
                    amount: entry.amount,
                    vaultAmountMicro: entry.vaultAmountMicro,
                    adjustmentBaseAmount: nil,
                    oneTimeAdjustmentMultiplier: nil,
                    tradeKind: .vaultInterest,
                    vaultInterestHour: Calendar.utcVaultCalendar.startOfHour(for: vaultInterestHour),
                    createdAt: createdAt,
                    updatedAt: updatedAt ?? createdAt,
                    deletedAt: deletedAt
                )
            case .vaultReward(let rewardId, let sourceName):
                return Trade(
                    id: entry.id,
                    taskId: nil,
                    recurringTaskId: nil,
                    rewardId: rewardId,
                    sourceName: sourceName,
                    amount: entry.amount,
                    vaultAmountMicro: entry.vaultAmountMicro,
                    adjustmentBaseAmount: entry.adjustmentBaseAmount,
                    oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
                    tradeKind: .vaultRewardPurchase,
                    createdAt: createdAt,
                    updatedAt: updatedAt ?? createdAt,
                    deletedAt: deletedAt
                )
            }
        }
    }

    private func upsertTrade(_ trade: Trade, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO trades (
                id, owner_id, task_id, recurring_task_id, reward_id, source_name, amount, vault_amount_micro, adjustment_base_amount, one_time_adjustment_multiplier, trade_kind, vault_interest_hour, created_at, updated_at, deleted_at, refunds_trade_id, server_revision
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                owner_id = excluded.owner_id,
                task_id = excluded.task_id,
                recurring_task_id = excluded.recurring_task_id,
                reward_id = excluded.reward_id,
                source_name = excluded.source_name,
                amount = excluded.amount,
                vault_amount_micro = excluded.vault_amount_micro,
                adjustment_base_amount = excluded.adjustment_base_amount,
                one_time_adjustment_multiplier = excluded.one_time_adjustment_multiplier,
                trade_kind = excluded.trade_kind,
                vault_interest_hour = excluded.vault_interest_hour,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                refunds_trade_id = excluded.refunds_trade_id,
                server_revision = excluded.server_revision
            """,
            bindings: tradeBindings(trade, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func notifySync(ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .trades, recordIDs: ids))
    }

    private func loadTrades(ownerID: String) -> [Trade] {
        let fetched = (try? database.query(
            """
            SELECT id, task_id, recurring_task_id, reward_id, source_name, amount, vault_amount_micro, adjustment_base_amount, one_time_adjustment_multiplier, trade_kind, vault_interest_hour, created_at, updated_at, deleted_at, refunds_trade_id, server_revision
            FROM trades
            WHERE owner_id = ?
            ORDER BY created_at ASC, id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL,
            map: Self.trade(from:)
        )) ?? []

        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private static func trade(from row: Row) -> Trade {
        Trade(
            id: RecordID(SQLiteColumn.text(row, index: 0)),
            taskId: SQLiteColumn.optionalText(row, index: 1).map { RecordID(rawValue: $0) },
            recurringTaskId: SQLiteColumn.optionalText(row, index: 2).map { RecordID(rawValue: $0) },
            rewardId: SQLiteColumn.optionalText(row, index: 3).map { RecordID(rawValue: $0) },
            sourceName: SQLiteColumn.optionalText(row, index: 4),
            amount: SQLiteColumn.int(row, index: 5),
            vaultAmountMicro: SQLiteColumn.optionalInt(row, index: 6),
            adjustmentBaseAmount: SQLiteColumn.optionalInt(row, index: 7),
            oneTimeAdjustmentMultiplier: SQLiteColumn.optionalDouble(row, index: 8),
            tradeKind: SQLiteColumn.optionalText(row, index: 9).flatMap(TradeKind.init(rawValue:))
                ?? Trade.defaultKind(taskId: SQLiteColumn.optionalText(row, index: 1).map { RecordID(rawValue: $0) }, recurringTaskId: SQLiteColumn.optionalText(row, index: 2).map { RecordID(rawValue: $0) }, rewardId: SQLiteColumn.optionalText(row, index: 3).map { RecordID(rawValue: $0) }),
            vaultInterestHour: SQLiteColumn.optionalDate(row, index: 10),
            createdAt: SQLiteColumn.date(row, index: 11),
            updatedAt: SQLiteColumn.date(row, index: 12),
            deletedAt: SQLiteColumn.optionalDate(row, index: 13),
            refundsTradeId: SQLiteColumn.optionalText(row, index: 14).map { RecordID(rawValue: $0) },
            serverRevision: SQLiteColumn.optionalInt64(row, index: 15)
        )
    }

    private func refreshCurrentTrades() {
        trades = loadTrades(ownerID: currentOwnerID)
    }

    private func replaceRows(ownerID: String, trades: [Trade], on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            "DELETE FROM trades WHERE owner_id = ?",
            bindings: [.text(ownerID)],
            on: databaseHandle
        )

        for trade in trades {
            try database.execute(
                """
                INSERT INTO trades (
                    id, owner_id, task_id, recurring_task_id, reward_id, source_name, amount, vault_amount_micro, adjustment_base_amount, one_time_adjustment_multiplier, trade_kind, vault_interest_hour, created_at, updated_at, deleted_at, refunds_trade_id, server_revision
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: tradeBindings(trade, ownerID: ownerID),
                on: databaseHandle
            )
        }
    }

    private func makeTradeOwnerMigration(
        source: [Trade],
        destination: [Trade]
    ) -> (mergedTrades: [Trade], migratedTradeIDs: [RecordID]) {
        let destinationActiveVaultInterestByHour = Dictionary(
            uniqueKeysWithValues: destination.compactMap { trade -> (Date, Trade)? in
                guard trade.deletedAt == nil,
                      trade.tradeKind == .vaultInterest else { return nil }
                return trade.vaultInterestHour.map { ($0, trade) }
            }
        )
        var combinedDestinationVaultInterestByID: [RecordID: Trade] = [:]
        let migratableSource = source.filter { trade in
            guard trade.deletedAt == nil,
                  trade.tradeKind == .vaultInterest,
                  let hour = trade.vaultInterestHour else {
                return true
            }
            guard let destinationInterest = destinationActiveVaultInterestByHour[hour] else {
                return true
            }

            // Behaviour: when an anonymous ledger and an existing account have
            // already materialized the same vault-interest hour, preserve the
            // local value by folding it into the account row. The backend and
            // local DB both enforce one active interest trade per owner/hour.
            combinedDestinationVaultInterestByID[destinationInterest.id] = combinedVaultInterest(
                destinationInterest: combinedDestinationVaultInterestByID[destinationInterest.id] ?? destinationInterest,
                sourceInterest: trade
            )
            return false
        }
        let destinationWithCombinedVaultInterest = destination.map { trade in
            combinedDestinationVaultInterestByID[trade.id] ?? trade
        }

        return (
            mergedTrades: OwnerScopedRecordSupport.mergeRecords(
                local: destinationWithCombinedVaultInterest,
                remote: migratableSource
            ),
            migratedTradeIDs: migratableSource.map(\.id) + combinedDestinationVaultInterestByID.keys
        )
    }

    private func combinedVaultInterest(
        destinationInterest: Trade,
        sourceInterest: Trade
    ) -> Trade {
        Trade(
            id: destinationInterest.id,
            taskId: nil,
            recurringTaskId: nil,
            rewardId: nil,
            sourceName: destinationInterest.sourceName,
            amount: 0,
            vaultAmountMicro: (destinationInterest.vaultAmountMicro ?? 0) + (sourceInterest.vaultAmountMicro ?? 0),
            adjustmentBaseAmount: nil,
            oneTimeAdjustmentMultiplier: nil,
            tradeKind: .vaultInterest,
            vaultInterestHour: destinationInterest.vaultInterestHour,
            createdAt: min(destinationInterest.createdAt, sourceInterest.createdAt),
            updatedAt: max(destinationInterest.updatedAt, sourceInterest.updatedAt),
            deletedAt: nil,
            refundsTradeId: nil,
            serverRevision: destinationInterest.serverRevision
        )
    }

    private func recalculateBalance(ownerID: String) throws {
        try database.transaction(at: databaseURL) { db in
            try self.recalculateBalance(ownerID: ownerID, on: db)
        }
    }

    private func recalculateBalance(ownerID: String, on databaseHandle: AppDatabaseHandle) throws {
        let total = try database.queryOne(
            """
            SELECT COALESCE(SUM(amount), 0)
            FROM trades
            WHERE owner_id = ?
                AND deleted_at IS NULL
                AND trade_kind IN ('taskCompletion', 'recurringTaskCompletion', 'rewardPurchase', 'vaultDeposit')
            """,
            bindings: [.text(ownerID)],
            on: databaseHandle
        ) { row in
            SQLiteColumn.int(row, index: 0)
        } ?? 0

        try database.execute(
            """
            INSERT INTO balance_projections (owner_id, balance, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(owner_id) DO UPDATE SET
                balance = excluded.balance,
                updated_at = excluded.updated_at
            """,
            bindings: [
                .text(ownerID),
                .int(Int64(total)),
                .double(Date().timeIntervalSince1970)
            ],
            on: databaseHandle
        )
    }

    private func tradeBindings(_ trade: Trade, ownerID: String) -> [SQLiteValue] {
        [
            .text(trade.id.rawValue),
            .text(ownerID),
            trade.taskId.map { .text($0.rawValue) } ?? .null,
            trade.recurringTaskId.map { .text($0.rawValue) } ?? .null,
            trade.rewardId.map { .text($0.rawValue) } ?? .null,
            trade.sourceName.map { .text($0) } ?? .null,
            .int(Int64(trade.amount)),
            trade.vaultAmountMicro.map { .int(Int64($0)) } ?? .null,
            trade.adjustmentBaseAmount.map { .int(Int64($0)) } ?? .null,
            trade.oneTimeAdjustmentMultiplier.map(SQLiteValue.double) ?? .null,
            .text(trade.tradeKind.rawValue),
            trade.vaultInterestHour.map { .double($0.timeIntervalSince1970) } ?? .null,
            .double(trade.createdAt.timeIntervalSince1970),
            .double(trade.updatedAt.timeIntervalSince1970),
            trade.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            trade.refundsTradeId.map { .text($0.rawValue) } ?? .null,
            trade.serverRevision.map { .int($0) } ?? .null
        ]
    }

    private func isUnresolvedSourceTrade(_ trade: Trade) -> Bool {
        trade.deletedAt == nil && !trade.isRefundTrade && !hasActiveRefund(for: trade.id)
    }

    private func hasActiveRefund(for tradeID: RecordID) -> Bool {
        tradeProjection.activeRefundedTradeIDs.contains(tradeID)
    }

    private func activeRefundedTradeIDs() -> Set<RecordID> {
        tradeProjection.activeRefundedTradeIDs
    }

    private func hasVaultInterest(for hour: Date) -> Bool {
        trades.contains { trade in
            trade.deletedAt == nil
                && trade.tradeKind == .vaultInterest
                && trade.vaultInterestHour == hour
        }
    }

    private func vaultBalanceMicro(before cutoff: Date?) -> Int {
        trades.reduce(into: 0) { total, trade in
            guard trade.deletedAt == nil else { return }
            if let cutoff, trade.createdAt >= cutoff { return }

            switch trade.tradeKind {
            case .vaultDeposit, .vaultInterest, .vaultRewardPurchase:
                total += trade.vaultAmountMicro ?? 0
            case .taskCompletion, .recurringTaskCompletion, .rewardPurchase:
                return
            }
        }
    }
}

private extension Calendar {
    static let utcVaultCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    func startOfHour(for date: Date) -> Date {
        let components = dateComponents([.year, .month, .day, .hour], from: date)
        return self.date(from: components) ?? date
    }

    func nextHourStart(after date: Date) -> Date {
        let hourStart = startOfHour(for: date)
        return self.date(byAdding: .hour, value: 1, to: hourStart) ?? hourStart.addingTimeInterval(60 * 60)
    }
}
