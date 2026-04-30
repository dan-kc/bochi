import Foundation

@Observable
@MainActor
final class TradeStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore

    private(set) var currentOwnerID: String
    private(set) var trades: [Trade] = []

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.syncStateStore = SyncStateStore(storageURL: self.databaseURL)
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        self.trades = loadTrades(ownerID: initialOwnerID)
        try? recalculateBalance(ownerID: initialOwnerID)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        trades = loadTrades(ownerID: ownerID)
        try? recalculateBalance(ownerID: ownerID)
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

    func addHabitTrade(
        id: RecordID? = nil,
        habitId: RecordID,
        amount: Int,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        addHabitTrades(
            entries: [(id: id ?? RecordID(), amount: amount)],
            habitId: habitId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func addTaskTrade(
        id: RecordID? = nil,
        taskId: RecordID,
        amount: Int,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        addTaskTrades(
            entries: [(id: id ?? RecordID(), amount: amount)],
            taskId: taskId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            shouldNotifySync: shouldNotifySync
        )
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
        addRewardPurchases(
            entries: [(id: id ?? RecordID(), amount: amount)],
            rewardId: rewardId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func addHabitTrades(
        entries: [(id: RecordID, amount: Int)],
        habitId: RecordID,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        guard !entries.isEmpty else { return }

        let rows = entries.map { entry in
            Trade(
                id: entry.id,
                taskId: nil,
                habitId: habitId,
                rewardId: nil,
                amount: entry.amount,
                createdAt: createdAt,
                updatedAt: updatedAt ?? createdAt,
                deletedAt: deletedAt
            )
        }

        upsertTrades(rows, markDirty: shouldNotifySync)
        if shouldNotifySync {
            SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .trades, recordIDs: rows.map(\.id)))
        }
    }

    func addTaskTrades(
        entries: [(id: RecordID, amount: Int)],
        taskId: RecordID,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        guard !entries.isEmpty else { return }

        let rows = entries.map { entry in
            Trade(
                id: entry.id,
                taskId: taskId,
                habitId: nil,
                rewardId: nil,
                amount: entry.amount,
                createdAt: createdAt,
                updatedAt: updatedAt ?? createdAt,
                deletedAt: deletedAt
            )
        }

        upsertTrades(rows, markDirty: shouldNotifySync)
        if shouldNotifySync {
            SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .trades, recordIDs: rows.map(\.id)))
        }
    }

    func addRewardPurchases(
        entries: [(id: RecordID, amount: Int)],
        rewardId: RecordID,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        guard !entries.isEmpty else { return }

        let rows = entries.map { entry in
            Trade(
                id: entry.id,
                taskId: nil,
                habitId: nil,
                rewardId: rewardId,
                amount: entry.amount,
                createdAt: createdAt,
                updatedAt: updatedAt ?? createdAt,
                deletedAt: deletedAt
            )
        }

        upsertTrades(rows, markDirty: shouldNotifySync)
        if shouldNotifySync {
            SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .trades, recordIDs: rows.map(\.id)))
        }
    }

    func addHabitTradeWithDate(habitId: RecordID, amount: Int, createdAt: Date) {
        addHabitTrade(habitId: habitId, amount: amount, createdAt: createdAt)
    }

    func addTaskTradeWithDate(taskId: RecordID, amount: Int, createdAt: Date) {
        addTaskTrade(taskId: taskId, amount: amount, createdAt: createdAt)
    }

    func addRewardPurchaseWithDate(rewardId: RecordID, amount: Int, createdAt: Date) {
        addRewardPurchase(rewardId: rewardId, amount: amount, createdAt: createdAt)
    }

    func habitTradeDates(habitId: RecordID) -> [Date] {
        trades.compactMap { trade in
            guard trade.habitId == habitId, trade.deletedAt == nil else { return nil }
            return trade.createdAt
        }
    }

    func habitCompletionCount(habitId: RecordID) -> Int {
        trades.reduce(into: 0) { count, trade in
            guard trade.habitId == habitId, trade.deletedAt == nil else { return }
            count += 1
        }
    }

    func rewardPurchaseDates(rewardId: RecordID) -> [Date] {
        trades.compactMap { trade in
            guard trade.rewardId == rewardId, trade.deletedAt == nil else { return nil }
            return trade.createdAt
        }
    }

    func tradesInPeriod(habitId: RecordID, days: Int) -> Int {
        let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
        return trades.filter {
            $0.habitId == habitId && $0.deletedAt == nil && $0.createdAt >= cutoff
        }.count
    }

    func rewardPurchasesInPeriod(rewardId: RecordID, days: Int) -> Int {
        let cutoff = Date(timeIntervalSinceNow: -Double(days) * 86400)
        return trades.filter {
            $0.rewardId == rewardId && $0.deletedAt == nil && $0.createdAt >= cutoff
        }.count
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

    func migrateTrades(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> [RecordID] {
        guard sourceOwnerID != destinationOwnerID else { return [] }
        let source = loadTrades(ownerID: sourceOwnerID)
        let destination = loadTrades(ownerID: destinationOwnerID)
        let merged = OwnerScopedRecordSupport.mergeRecords(local: destination, remote: source)

        // Remove the local-owner rows before re-inserting the merged account view
        // so a sign-in migration does not trip the global trade-id uniqueness rule.
        try replaceRows(ownerID: sourceOwnerID, trades: [], on: databaseHandle)
        try replaceRows(ownerID: destinationOwnerID, trades: merged, on: databaseHandle)
        try recalculateBalance(ownerID: destinationOwnerID, on: databaseHandle)
        try recalculateBalance(ownerID: sourceOwnerID, on: databaseHandle)
        return source.map(\.id)
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

    private func upsertTrade(_ trade: Trade, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO trades (
                id, owner_id, task_id, habit_id, reward_id, amount, created_at, updated_at, deleted_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                owner_id = excluded.owner_id,
                task_id = excluded.task_id,
                habit_id = excluded.habit_id,
                reward_id = excluded.reward_id,
                amount = excluded.amount,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at
            """,
            bindings: tradeBindings(trade, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func loadTrades(ownerID: String) -> [Trade] {
        let fetched = (try? database.query(
            """
            SELECT id, task_id, habit_id, reward_id, amount, created_at, updated_at, deleted_at
            FROM trades
            WHERE owner_id = ?
            ORDER BY created_at ASC, id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            Trade(
                id: RecordID(SQLiteColumn.text(row, index: 0)),
                taskId: SQLiteColumn.optionalText(row, index: 1).map { RecordID(rawValue: $0) },
                habitId: SQLiteColumn.optionalText(row, index: 2).map { RecordID(rawValue: $0) },
                rewardId: SQLiteColumn.optionalText(row, index: 3).map { RecordID(rawValue: $0) },
                amount: SQLiteColumn.int(row, index: 4),
                createdAt: SQLiteColumn.date(row, index: 5),
                updatedAt: SQLiteColumn.date(row, index: 6),
                deletedAt: SQLiteColumn.optionalDate(row, index: 7)
            )
        }) ?? []

        return OwnerScopedRecordSupport.sorted(fetched)
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
                    id, owner_id, task_id, habit_id, reward_id, amount, created_at, updated_at, deleted_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: tradeBindings(trade, ownerID: ownerID),
                on: databaseHandle
            )
        }
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
            WHERE owner_id = ? AND deleted_at IS NULL
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
            trade.habitId.map { .text($0.rawValue) } ?? .null,
            trade.rewardId.map { .text($0.rawValue) } ?? .null,
            .int(Int64(trade.amount)),
            .double(trade.createdAt.timeIntervalSince1970),
            .double(trade.updatedAt.timeIntervalSince1970),
            trade.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null
        ]
    }
}
