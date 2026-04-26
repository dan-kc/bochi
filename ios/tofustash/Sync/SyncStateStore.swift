import Foundation

@MainActor
final class SyncStateStore {
    struct DirtyState: Codable, Equatable {
        var habits: [RecordID] = []
        var trades: [RecordID] = []
        var tags: [RecordID] = []
        var habitTags: [RecordID] = []
        var rewards: [RecordID] = []
        var rewardTags: [RecordID] = []
        var generalDifficulty: Bool = false
    }

    struct UserSyncState: Codable, Equatable {
        var lastSync: Date?
        var lastFullSyncAt: Date?
        var dirty = DirtyState()
    }

    private let databaseURL: URL
    private let database = AppDatabase.shared

    init(storageURL: URL? = nil) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        _ = try? database.connection(at: databaseURL)
    }

    func state(for userID: String) -> UserSyncState {
        let checkpoint: (lastSync: Date?, lastFullSyncAt: Date?)
        do {
            checkpoint = try database.queryOne(
                """
                SELECT last_sync_server_time, last_full_sync_at
                FROM sync_state
                WHERE user_id = ?
                """,
                bindings: [.text(userID)],
                at: databaseURL
            ) { row in
                (
                    lastSync: SQLiteColumn.optionalDate(row, index: 0),
                    lastFullSyncAt: SQLiteColumn.optionalDate(row, index: 1)
                )
            } ?? (nil, nil)
        } catch {
            assertionFailure("Failed to load sync state checkpoint: \(error)")
            checkpoint = (nil, nil)
        }

        let dirtyRecords = fetchDirtyRecords(for: userID)
        let dirtyFlags = fetchDirtyFlags(for: userID)

        return UserSyncState(
            lastSync: checkpoint.lastSync,
            lastFullSyncAt: checkpoint.lastFullSyncAt,
            dirty: DirtyState(
                habits: dirtyRecords[.habits] ?? [],
                trades: dirtyRecords[.trades] ?? [],
                tags: dirtyRecords[.tags] ?? [],
                habitTags: dirtyRecords[.habitTags] ?? [],
                rewards: dirtyRecords[.rewards] ?? [],
                rewardTags: dirtyRecords[.rewardTags] ?? [],
                generalDifficulty: dirtyFlags.contains(.generalDifficulty)
            )
        )
    }

    func markDirty(userID: String, kind: SyncEntityKind, ids: [RecordID]) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.ensureSyncStateRow(userID: userID, on: db)

                switch kind {
                case .generalDifficulty:
                    try self.database.execute(
                        """
                        INSERT OR IGNORE INTO dirty_flags (user_id, entity_kind)
                        VALUES (?, ?)
                        """,
                        bindings: [.text(userID), .text(kind.rawValue)],
                        on: db
                    )
                default:
                    for id in ids {
                        try self.database.execute(
                            """
                            INSERT OR IGNORE INTO dirty_records (user_id, entity_kind, record_id)
                            VALUES (?, ?, ?)
                            """,
                            bindings: [.text(userID), .text(kind.rawValue), .text(id.rawValue)],
                            on: db
                        )
                    }
                }
            }
        } catch {
            assertionFailure("Failed to mark dirty sync state: \(error)")
        }
    }

    func clearDirty(userID: String, kind: SyncEntityKind, ids: Set<RecordID>) {
        guard !ids.isEmpty else { return }
        do {
            try database.transaction(at: databaseURL) { db in
                for id in ids {
                    try self.database.execute(
                        """
                        DELETE FROM dirty_records
                        WHERE user_id = ? AND entity_kind = ? AND record_id = ?
                        """,
                        bindings: [.text(userID), .text(kind.rawValue), .text(id.rawValue)],
                        on: db
                    )
                }
            }
        } catch {
            assertionFailure("Failed to clear dirty sync state: \(error)")
        }
    }

    func clearFlag(userID: String, kind: SyncEntityKind) {
        do {
            try database.execute(
                """
                DELETE FROM dirty_flags
                WHERE user_id = ? AND entity_kind = ?
                """,
                bindings: [.text(userID), .text(kind.rawValue)],
                at: databaseURL
            )
        } catch {
            assertionFailure("Failed to clear sync dirty flag: \(error)")
        }
    }

    func clearAllDirty(userID: String) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.database.execute(
                    "DELETE FROM dirty_records WHERE user_id = ?",
                    bindings: [.text(userID)],
                    on: db
                )
                try self.database.execute(
                    "DELETE FROM dirty_flags WHERE user_id = ?",
                    bindings: [.text(userID)],
                    on: db
                )
            }
        } catch {
            assertionFailure("Failed to clear all dirty sync state: \(error)")
        }
    }

    func setLastSync(userID: String, serverTime: Date) {
        upsertSyncState(userID: userID, lastSync: serverTime, keepLastFullSync: true, fullSyncRequired: false)
    }

    func forceFullSyncOnNextRun(userID: String) {
        upsertSyncState(userID: userID, lastSync: nil, keepLastFullSync: true, fullSyncRequired: true)
    }

    func shouldPerformFullSync(userID: String, now: Date = Date()) -> Bool {
        let current = state(for: userID)
        guard current.lastSync != nil else {
            return true
        }
        guard let lastFullSyncAt = current.lastFullSyncAt else {
            return true
        }

        let fullSyncRequired: Bool
        do {
            fullSyncRequired = try database.queryOne(
                "SELECT full_sync_required FROM sync_state WHERE user_id = ?",
                bindings: [.text(userID)],
                at: databaseURL
            ) { row in
                SQLiteColumn.int(row, index: 0) != 0
            } ?? false
        } catch {
            assertionFailure("Failed to load full sync requirement: \(error)")
            fullSyncRequired = true
        }

        return fullSyncRequired || now.timeIntervalSince(lastFullSyncAt) >= 24 * 60 * 60
    }

    func recordFullSync(userID: String, completedAt: Date = Date()) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.ensureSyncStateRow(userID: userID, on: db)
                try self.database.execute(
                    """
                    UPDATE sync_state
                    SET last_full_sync_at = ?, full_sync_required = 0
                    WHERE user_id = ?
                    """,
                    bindings: [.double(completedAt.timeIntervalSince1970), .text(userID)],
                    on: db
                )
            }
        } catch {
            assertionFailure("Failed to record full sync completion: \(error)")
        }
    }

    private func upsertSyncState(
        userID: String,
        lastSync: Date?,
        keepLastFullSync: Bool,
        fullSyncRequired: Bool
    ) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.ensureSyncStateRow(userID: userID, on: db)
                let existing = try self.database.queryOne(
                    "SELECT last_full_sync_at FROM sync_state WHERE user_id = ?",
                    bindings: [.text(userID)],
                    on: db
                ) { row in
                    SQLiteColumn.optionalDate(row, index: 0)
                }

                try self.database.execute(
                    """
                    UPDATE sync_state
                    SET last_sync_server_time = ?,
                        last_full_sync_at = ?,
                        full_sync_required = ?
                    WHERE user_id = ?
                    """,
                    bindings: [
                        lastSync.map { .double($0.timeIntervalSince1970) } ?? .null,
                        keepLastFullSync ? (existing.map { .double($0.timeIntervalSince1970) } ?? .null) : .null,
                        .int(fullSyncRequired ? 1 : 0),
                        .text(userID)
                    ],
                    on: db
                )
            }
        } catch {
            assertionFailure("Failed to update sync state: \(error)")
        }
    }

    private func fetchDirtyRecords(for userID: String) -> [SyncEntityKind: [RecordID]] {
        let rows = (try? database.query(
            """
            SELECT entity_kind, record_id
            FROM dirty_records
            WHERE user_id = ?
            ORDER BY entity_kind ASC, record_id ASC
            """,
            bindings: [.text(userID)],
            at: databaseURL
        ) { row in
            (
                SQLiteColumn.text(row, index: 0),
                RecordID(SQLiteColumn.text(row, index: 1))
            )
        }) ?? []

        var grouped: [SyncEntityKind: [RecordID]] = [:]
        for (kindRawValue, id) in rows {
            guard let kind = SyncEntityKind(rawValue: kindRawValue) else { continue }
            grouped[kind, default: []].append(id)
        }
        return grouped
    }

    private func fetchDirtyFlags(for userID: String) -> Set<SyncEntityKind> {
        let flags = (try? database.query(
            """
            SELECT entity_kind
            FROM dirty_flags
            WHERE user_id = ?
            """,
            bindings: [.text(userID)],
            at: databaseURL
        ) { row in
            SQLiteColumn.text(row, index: 0)
        }) ?? []

        return Set(flags.compactMap(SyncEntityKind.init(rawValue:)))
    }

    private func ensureSyncStateRow(userID: String, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT OR IGNORE INTO sync_state (user_id, last_sync_server_time, last_full_sync_at, full_sync_required)
            VALUES (?, NULL, NULL, 1)
            """,
            bindings: [.text(userID)],
            on: databaseHandle
        )
    }
}
