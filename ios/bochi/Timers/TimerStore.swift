import Foundation
import GRDB

// Sync flow: signed-in timer edits mark records dirty and publish mutations;
// server replacements refresh the store without enqueueing another sync.
@Observable
@MainActor
final class TimerStore {
    private(set) var timers: [BochiTimer] = []

    internal let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore
    private var currentOwnerID = StorageOwner.local
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(storageURL: URL? = nil, syncStateStore: SyncStateStore? = nil) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.syncStateStore = syncStateStore ?? SyncStateStore(storageURL: storageURL)
        _ = try? database.connection(at: databaseURL)
        refreshCurrentTimers()
    }

    var activeTimers: [BochiTimer] {
        timers.filter { $0.deletedAt == nil }
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        refreshCurrentTimers()
    }

    func timer(id: RecordID) -> BochiTimer? {
        activeTimers.first { $0.id == id }
    }

    @discardableResult
    func addTimer(
        id: RecordID = RecordID(),
        name: String,
        intervals: [TimerInterval],
        now: Date = Date()
    ) -> BochiTimer? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 50, let normalizedIntervals = normalizedIntervals(intervals) else { return nil }

        let timer = BochiTimer(
            id: id,
            name: trimmedName,
            intervals: normalizedIntervals,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        upsert(timer, markDirty: true)
        notifySync(ids: [id])
        return timer
    }

    func updateTimer(
        id: RecordID,
        name: String? = nil,
        intervals: [TimerInterval]? = nil,
        deletedAt: Date?? = nil,
        now: Date = Date()
    ) {
        guard let existing = timers.first(where: { $0.id == id }) else { return }
        let nextName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? existing.name
        guard !nextName.isEmpty, nextName.count <= 50 else { return }
        let nextIntervals: [TimerInterval]
        if let intervals {
            guard let normalizedIntervals = normalizedIntervals(intervals) else { return }
            nextIntervals = normalizedIntervals
        } else {
            nextIntervals = existing.intervals
        }

        let timer = BochiTimer(
            id: existing.id,
            name: nextName,
            intervals: nextIntervals,
            createdAt: existing.createdAt,
            updatedAt: now,
            deletedAt: deletedAt ?? existing.deletedAt,
            serverRevision: existing.serverRevision
        )
        upsert(timer, markDirty: true)
        notifySync(ids: [id])
    }

    func deleteTimer(id: RecordID, deletedAt: Date = Date()) {
        updateTimer(id: id, deletedAt: .some(deletedAt), now: deletedAt)
    }

    func getDirtyTimers(ids: Set<RecordID>) -> [BochiTimer] {
        timers.filter { ids.contains($0.id) }
    }

    func persistReplacedTimers(_ timers: [BochiTimer]) throws {
        try database.transaction(at: databaseURL) { db in
            try self.replaceRows(ownerID: self.currentOwnerID, timers: timers, on: db)
        }
        refreshCurrentTimers()
    }

    func replaceTimers(
        _ authoritativeTimers: [BochiTimer],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try replaceRows(
            ownerID: currentOwnerID,
            timers: OwnerScopedRecordSupport.sorted(authoritativeTimers),
            on: databaseHandle
        )
    }

    func purgeDeletedTimers(excluding dirtyIDs: Set<RecordID>, on databaseHandle: AppDatabaseHandle) throws {
        if dirtyIDs.isEmpty {
            try database.execute(
                "DELETE FROM timers WHERE owner_id = ? AND deleted_at IS NOT NULL",
                bindings: [.text(currentOwnerID)],
                on: databaseHandle
            )
            return
        }

        let placeholders = Array(repeating: "?", count: dirtyIDs.count).joined(separator: ", ")
        let bindings: [SQLiteValue] = [SQLiteValue.text(currentOwnerID)]
            + dirtyIDs.sorted { $0.rawValue < $1.rawValue }.map { SQLiteValue.text($0.rawValue) }
        try database.execute(
            "DELETE FROM timers WHERE owner_id = ? AND deleted_at IS NOT NULL AND id NOT IN (\(placeholders))",
            bindings: bindings,
            on: databaseHandle
        )
    }

    func migrateTimers(from sourceOwnerID: String, to destinationOwnerID: String, on databaseHandle: AppDatabaseHandle) throws -> [RecordID] {
        guard sourceOwnerID != destinationOwnerID else { return [] }
        let sourceIDs = try loadTimers(ownerID: sourceOwnerID, on: databaseHandle).map(\.id)
        guard !sourceIDs.isEmpty else { return [] }
        try database.execute(
            "UPDATE timers SET owner_id = ? WHERE owner_id = ?",
            bindings: [.text(destinationOwnerID), .text(sourceOwnerID)],
            on: databaseHandle
        )
        return sourceIDs
    }

    private func upsert(_ timer: BochiTimer, markDirty: Bool) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.upsert(timer, ownerID: self.currentOwnerID, on: db)
                if markDirty, self.currentOwnerID != StorageOwner.local {
                    try self.syncStateStore.markDirty(userID: self.currentOwnerID, kind: .timers, ids: [timer.id], on: db)
                }
            }
        } catch {
            assertionFailure("Failed to upsert timer: \(error)")
            return
        }
        refreshCurrentTimers()
    }

    private func upsert(_ timer: BochiTimer, ownerID: String, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO timers (
                id, owner_id, name, intervals_json, created_at, updated_at, deleted_at, server_revision
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                owner_id = excluded.owner_id,
                name = excluded.name,
                intervals_json = excluded.intervals_json,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                server_revision = excluded.server_revision
            """,
            bindings: timerBindings(timer, ownerID: ownerID),
            on: databaseHandle
        )
    }

    private func replaceRows(ownerID: String, timers: [BochiTimer], on databaseHandle: AppDatabaseHandle) throws {
        try database.execute("CREATE TEMP TABLE IF NOT EXISTS timer_replacement_ids (id TEXT PRIMARY KEY)", on: databaseHandle)
        try database.execute("DELETE FROM timer_replacement_ids", on: databaseHandle)
        for timer in timers {
            try database.execute(
                "INSERT OR IGNORE INTO timer_replacement_ids (id) VALUES (?)",
                bindings: [.text(timer.id.rawValue)],
                on: databaseHandle
            )
        }
        try database.execute(
            """
            DELETE FROM timers
            WHERE owner_id = ?
              AND NOT EXISTS (
                  SELECT 1 FROM timer_replacement_ids replacement
                  WHERE replacement.id = timers.id
              )
            """,
            bindings: [.text(ownerID)],
            on: databaseHandle
        )

        for timer in timers {
            try upsert(timer, ownerID: ownerID, on: databaseHandle)
        }
        try database.execute("DELETE FROM timer_replacement_ids", on: databaseHandle)
    }

    private func loadTimers(ownerID: String) -> [BochiTimer] {
        (try? database.query(
            """
            SELECT id, name, intervals_json, created_at, updated_at, deleted_at, server_revision
            FROM timers
            WHERE owner_id = ?
            ORDER BY created_at ASC, id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            timer(from: row)
        }) ?? []
    }

    private func loadTimers(ownerID: String, on databaseHandle: AppDatabaseHandle) throws -> [BochiTimer] {
        try database.query(
            """
            SELECT id, name, intervals_json, created_at, updated_at, deleted_at, server_revision
            FROM timers
            WHERE owner_id = ?
            ORDER BY created_at ASC, id ASC
            """,
            bindings: [.text(ownerID)],
            on: databaseHandle
        ) { row in
            timer(from: row)
        }
    }

    private func refreshCurrentTimers() {
        timers = OwnerScopedRecordSupport.sorted(loadTimers(ownerID: currentOwnerID))
    }

    private func timer(from row: GRDB.Row) -> BochiTimer {
        let intervalsData = Data(SQLiteColumn.text(row, index: 2).utf8)
        let intervals = (try? decoder.decode([TimerInterval].self, from: intervalsData)) ?? []
        return BochiTimer(
            id: RecordID(SQLiteColumn.text(row, index: 0)),
            name: SQLiteColumn.text(row, index: 1),
            intervals: intervals,
            createdAt: SQLiteColumn.date(row, index: 3),
            updatedAt: SQLiteColumn.date(row, index: 4),
            deletedAt: SQLiteColumn.optionalDate(row, index: 5),
            serverRevision: SQLiteColumn.optionalInt64(row, index: 6)
        )
    }

    private func timerBindings(_ timer: BochiTimer, ownerID: String) -> [SQLiteValue] {
        let intervalsData = (try? encoder.encode(timer.intervals)) ?? Data("[]".utf8)
        return [
            .text(timer.id.rawValue),
            .text(ownerID),
            .text(timer.name),
            .text(String(data: intervalsData, encoding: .utf8) ?? "[]"),
            .double(timer.createdAt.timeIntervalSince1970),
            .double(timer.updatedAt.timeIntervalSince1970),
            timer.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            timer.serverRevision.map { .int($0) } ?? .null
        ]
    }

    private func notifySync(ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .timers, recordIDs: ids))
    }

    private func normalizedIntervals(_ intervals: [TimerInterval]) -> [TimerInterval]? {
        guard !intervals.isEmpty else { return nil }
        let normalized = intervals.map { interval in
            TimerInterval(
                name: String(interval.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50)),
                durationSeconds: interval.durationSeconds
            )
        }
        guard normalized.allSatisfy({ !$0.name.isEmpty && (1...43_200).contains($0.durationSeconds) }) else {
            return nil
        }
        return normalized
    }
}
