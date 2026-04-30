import Foundation

@MainActor
final class SyncStateStore {
    struct DirtyRecordVersion: Equatable {
        let id: RecordID
        let generation: Int64
    }

    struct DirtyState: Equatable {
        var tasks: [DirtyRecordVersion] = []
        var habits: [DirtyRecordVersion] = []
        var trades: [DirtyRecordVersion] = []
        var tags: [DirtyRecordVersion] = []
        var taskTags: [DirtyRecordVersion] = []
        var taskTaskDependencies: [DirtyRecordVersion] = []
        var taskHabitDependencies: [DirtyRecordVersion] = []
        var habitTags: [DirtyRecordVersion] = []
        var rewards: [DirtyRecordVersion] = []
        var rewardTags: [DirtyRecordVersion] = []
        var generalDifficultyGeneration: Int64?

        var generalDifficulty: Bool {
            generalDifficultyGeneration != nil
        }
    }

    struct UserSyncState: Equatable {
        var lastSyncCursor: String?
        var lastSyncTime: Date?
        var lastFullSyncAt: Date?
        var dirty = DirtyState()
    }

    internal let databaseURL: URL
    private let database = AppDatabase.shared

    init(storageURL: URL? = nil) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        _ = try? database.connection(at: databaseURL)
    }

    func state(for userID: String) -> UserSyncState {
        do {
            return try database.transaction(at: databaseURL) { db in
                try self.state(for: userID, on: db)
            }
        } catch {
            assertionFailure("Failed to load sync state: \(error)")
            return UserSyncState()
        }
    }

    func state(for userID: String, on databaseHandle: AppDatabaseHandle) throws -> UserSyncState {
        let checkpoint: (lastSyncCursor: String?, lastSyncTime: Date?, lastFullSyncAt: Date?) = try database.queryOne(
            """
            SELECT last_sync_cursor, last_sync_server_time, last_full_sync_at
            FROM sync_state
            WHERE user_id = ?
            """,
            bindings: [.text(userID)],
            on: databaseHandle
        ) { row in
            (
                lastSyncCursor: SQLiteColumn.optionalText(row, index: 0),
                lastSyncTime: SQLiteColumn.optionalDate(row, index: 1),
                lastFullSyncAt: SQLiteColumn.optionalDate(row, index: 2)
            )
        } ?? (lastSyncCursor: nil, lastSyncTime: nil, lastFullSyncAt: nil)

        let dirtyRecords = try fetchDirtyRecords(for: userID, on: databaseHandle)
        let dirtyFlags = try fetchDirtyFlags(for: userID, on: databaseHandle)

        return UserSyncState(
            lastSyncCursor: checkpoint.lastSyncCursor,
            lastSyncTime: checkpoint.lastSyncTime,
            lastFullSyncAt: checkpoint.lastFullSyncAt,
            dirty: DirtyState(
                tasks: dirtyRecords[.tasks] ?? [],
                habits: dirtyRecords[.habits] ?? [],
                trades: dirtyRecords[.trades] ?? [],
                tags: dirtyRecords[.tags] ?? [],
                taskTags: dirtyRecords[.taskTags] ?? [],
                taskTaskDependencies: dirtyRecords[.taskTaskDependencies] ?? [],
                taskHabitDependencies: dirtyRecords[.taskHabitDependencies] ?? [],
                habitTags: dirtyRecords[.habitTags] ?? [],
                rewards: dirtyRecords[.rewards] ?? [],
                rewardTags: dirtyRecords[.rewardTags] ?? [],
                generalDifficultyGeneration: dirtyFlags[.generalDifficulty]
            )
        )
    }

    func markDirty(userID: String, kind: SyncEntityKind, ids: [RecordID]) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.markDirty(userID: userID, kind: kind, ids: ids, on: db)
            }
        } catch {
            assertionFailure("Failed to mark dirty sync state: \(error)")
        }
    }

    func markDirty(
        userID: String,
        kind: SyncEntityKind,
        ids: [RecordID],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try ensureSyncStateRow(userID: userID, on: databaseHandle)
        let generation = try nextMutationGeneration(userID: userID, on: databaseHandle)

        switch kind {
        case .generalDifficulty:
            try database.execute(
                """
                INSERT INTO dirty_flags (user_id, entity_kind, mutation_generation)
                VALUES (?, ?, ?)
                ON CONFLICT(user_id, entity_kind) DO UPDATE SET
                    mutation_generation = excluded.mutation_generation
                """,
                bindings: [.text(userID), .text(kind.rawValue), .int(generation)],
                on: databaseHandle
            )
        default:
            for id in ids {
                try database.execute(
                    """
                    INSERT INTO dirty_records (user_id, entity_kind, record_id, mutation_generation)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(user_id, entity_kind, record_id) DO UPDATE SET
                        mutation_generation = excluded.mutation_generation
                    """,
                    bindings: [.text(userID), .text(kind.rawValue), .text(id.rawValue), .int(generation)],
                    on: databaseHandle
                )
            }
        }
    }

    func completeSync(
        userID: String,
        snapshot: UserSyncState,
        serverCursor: String,
        serverTime: Date,
        completedFullSync: Bool,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try ensureSyncStateRow(userID: userID, on: databaseHandle)
        try clearSnapshot(userID: userID, snapshot: snapshot, on: databaseHandle)
        try updateCheckpoint(
            userID: userID,
            serverCursor: serverCursor,
            serverTime: serverTime,
            completedFullSync: completedFullSync,
            on: databaseHandle
        )
    }

    func updateCheckpoint(
        userID: String,
        serverCursor: String,
        serverTime: Date,
        completedFullSync: Bool,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try ensureSyncStateRow(userID: userID, on: databaseHandle)
        try database.execute(
            """
            UPDATE sync_state
            SET last_sync_cursor = ?,
                last_sync_server_time = ?,
                last_full_sync_at = CASE WHEN ? != 0 THEN ? ELSE last_full_sync_at END,
                full_sync_required = 0
            WHERE user_id = ?
            """,
            bindings: [
                .text(serverCursor),
                .double(serverTime.timeIntervalSince1970),
                .int(completedFullSync ? 1 : 0),
                .double(serverTime.timeIntervalSince1970),
                .text(userID)
            ],
            on: databaseHandle
        )
    }

    func forceFullSyncOnNextRun(userID: String) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.forceFullSyncOnNextRun(userID: userID, on: db)
            }
        } catch {
            assertionFailure("Failed to mark full sync required: \(error)")
        }
    }

    func forceFullSyncOnNextRun(userID: String, on databaseHandle: AppDatabaseHandle) throws {
        try ensureSyncStateRow(userID: userID, on: databaseHandle)
        try database.execute(
            """
            UPDATE sync_state
            SET last_sync_cursor = NULL,
                last_sync_server_time = NULL,
                full_sync_required = 1
            WHERE user_id = ?
            """,
            bindings: [.text(userID)],
            on: databaseHandle
        )
    }

    func shouldPerformFullSync(userID: String, now: Date = Date()) -> Bool {
        do {
            return try database.transaction(at: databaseURL) { db in
                let current = try self.state(for: userID, on: db)
                guard current.lastSyncCursor != nil else {
                    return true
                }
                guard let lastFullSyncAt = current.lastFullSyncAt else {
                    return true
                }

                let fullSyncRequired = try self.database.queryOne(
                    "SELECT full_sync_required FROM sync_state WHERE user_id = ?",
                    bindings: [.text(userID)],
                    on: db
                ) { row in
                    SQLiteColumn.int(row, index: 0) != 0
                } ?? false

                return fullSyncRequired || now.timeIntervalSince(lastFullSyncAt) >= 24 * 60 * 60
            }
        } catch {
            assertionFailure("Failed to load full sync requirement: \(error)")
            return true
        }
    }

    private func clearSnapshot(
        userID: String,
        snapshot: UserSyncState,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try clearDirty(userID: userID, kind: .tasks, versions: snapshot.dirty.tasks, on: databaseHandle)
        try clearDirty(userID: userID, kind: .habits, versions: snapshot.dirty.habits, on: databaseHandle)
        try clearDirty(userID: userID, kind: .trades, versions: snapshot.dirty.trades, on: databaseHandle)
        try clearDirty(userID: userID, kind: .tags, versions: snapshot.dirty.tags, on: databaseHandle)
        try clearDirty(userID: userID, kind: .taskTags, versions: snapshot.dirty.taskTags, on: databaseHandle)
        try clearDirty(userID: userID, kind: .taskTaskDependencies, versions: snapshot.dirty.taskTaskDependencies, on: databaseHandle)
        try clearDirty(userID: userID, kind: .taskHabitDependencies, versions: snapshot.dirty.taskHabitDependencies, on: databaseHandle)
        try clearDirty(userID: userID, kind: .habitTags, versions: snapshot.dirty.habitTags, on: databaseHandle)
        try clearDirty(userID: userID, kind: .rewards, versions: snapshot.dirty.rewards, on: databaseHandle)
        try clearDirty(userID: userID, kind: .rewardTags, versions: snapshot.dirty.rewardTags, on: databaseHandle)

        if let generation = snapshot.dirty.generalDifficultyGeneration {
            try database.execute(
                """
                DELETE FROM dirty_flags
                WHERE user_id = ? AND entity_kind = ? AND mutation_generation = ?
                """,
                bindings: [.text(userID), .text(SyncEntityKind.generalDifficulty.rawValue), .int(generation)],
                on: databaseHandle
            )
        }
    }

    private func clearDirty(
        userID: String,
        kind: SyncEntityKind,
        versions: [DirtyRecordVersion],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        for version in versions {
            try database.execute(
                """
                DELETE FROM dirty_records
                WHERE user_id = ? AND entity_kind = ? AND record_id = ? AND mutation_generation = ?
                """,
                bindings: [
                    .text(userID),
                    .text(kind.rawValue),
                    .text(version.id.rawValue),
                    .int(version.generation)
                ],
                on: databaseHandle
            )
        }
    }

    private func fetchDirtyRecords(
        for userID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> [SyncEntityKind: [DirtyRecordVersion]] {
        let rows = try database.query(
            """
            SELECT entity_kind, record_id, mutation_generation
            FROM dirty_records
            WHERE user_id = ?
            ORDER BY entity_kind ASC, record_id ASC
            """,
            bindings: [.text(userID)],
            on: databaseHandle
        ) { row in
            (
                SQLiteColumn.text(row, index: 0),
                RecordID(SQLiteColumn.text(row, index: 1)),
                Int64(SQLiteColumn.int(row, index: 2))
            )
        }

        var grouped: [SyncEntityKind: [DirtyRecordVersion]] = [:]
        for (kindRawValue, id, generation) in rows {
            guard let kind = SyncEntityKind(rawValue: kindRawValue) else { continue }
            grouped[kind, default: []].append(DirtyRecordVersion(id: id, generation: generation))
        }
        return grouped
    }

    private func fetchDirtyFlags(
        for userID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> [SyncEntityKind: Int64] {
        let rows = try database.query(
            """
            SELECT entity_kind, mutation_generation
            FROM dirty_flags
            WHERE user_id = ?
            """,
            bindings: [.text(userID)],
            on: databaseHandle
        ) { row in
            (
                SQLiteColumn.text(row, index: 0),
                Int64(SQLiteColumn.int(row, index: 1))
            )
        }

        var flags: [SyncEntityKind: Int64] = [:]
        for (kindRawValue, generation) in rows {
            guard let kind = SyncEntityKind(rawValue: kindRawValue) else { continue }
            flags[kind] = generation
        }
        return flags
    }

    private func ensureSyncStateRow(userID: String, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT OR IGNORE INTO sync_state (
                user_id,
                last_sync_server_time,
                last_full_sync_at,
                full_sync_required,
                last_sync_cursor,
                last_mutation_generation
            )
            VALUES (?, NULL, NULL, 1, NULL, 0)
            """,
            bindings: [.text(userID)],
            on: databaseHandle
        )
    }

    private func nextMutationGeneration(userID: String, on databaseHandle: AppDatabaseHandle) throws -> Int64 {
        let generation = try database.queryOne(
            """
            UPDATE sync_state
            SET last_mutation_generation = last_mutation_generation + 1
            WHERE user_id = ?
            RETURNING last_mutation_generation
            """,
            bindings: [.text(userID)],
            on: databaseHandle
        ) { row in
            Int64(SQLiteColumn.int(row, index: 0))
        }

        return generation ?? 0
    }
}
