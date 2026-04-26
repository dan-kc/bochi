import Foundation

@Observable
@MainActor
final class HabitStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore

    private(set) var currentOwnerID: String
    private(set) var habits: [Habit] = []

    var activeHabits: [Habit] {
        habits.filter { $0.deletedAt == nil }
    }

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.syncStateStore = SyncStateStore(storageURL: self.databaseURL)
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        self.habits = loadHabits(ownerID: initialOwnerID)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        habits = loadHabits(ownerID: ownerID)
    }

    func migrateHabits(from sourceOwnerID: String, to destinationOwnerID: String) -> [RecordID] {
        guard sourceOwnerID != destinationOwnerID else { return [] }
        do {
            let migratedIDs = try database.transaction(at: databaseURL) { db in
                try self.migrateHabits(from: sourceOwnerID, to: destinationOwnerID, on: db)
            }
            refreshCurrentHabits()
            return migratedIDs
        } catch {
            assertionFailure("Failed to migrate habits: \(error)")
            return []
        }
    }

    @discardableResult
    func addHabit(
        id: RecordID? = nil,
        name: String,
        description: String = "",
        frequency: Double? = nil,
        difficultyTier: HabitDifficultyTier? = nil,
        durationSeconds: Int? = nil,
        lockoutDurationSeconds: Int? = nil,
        skipConsequence: Int? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) -> Habit? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else {
            return nil
        }

        let canonicalID = id ?? RecordID()
        let now = Date()
        let habit = Habit(
            id: canonicalID,
            name: trimmedName,
            description: description,
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deletedAt: deletedAt,
            frequency: frequency,
            difficultyTier: difficultyTier,
            durationSeconds: durationSeconds,
            lockoutDurationSeconds: lockoutDurationSeconds,
            skipConsequence: skipConsequence
        )

        upsert(habit, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(ids: [habit.id])
        }
        return habit
    }

    func deleteHabit(id: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        guard let existing = habits.first(where: { $0.id == id }) else { return }
        let deleted = Habit(
            id: existing.id,
            name: existing.name,
            description: existing.description,
            createdAt: existing.createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt,
            frequency: existing.frequency,
            difficultyTier: existing.difficultyTier,
            durationSeconds: existing.durationSeconds,
            lockoutDurationSeconds: existing.lockoutDurationSeconds,
            skipConsequence: existing.skipConsequence
        )

        upsert(deleted, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(ids: [id])
        }
    }

    func updateHabit(
        id: RecordID,
        name: String? = nil,
        description: String? = nil,
        frequency: Double?? = nil,
        difficultyTier: HabitDifficultyTier?? = nil,
        durationSeconds: Int?? = nil,
        lockoutDurationSeconds: Int?? = nil,
        skipConsequence: Int?? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date?? = nil,
        shouldNotifySync: Bool = true
    ) {
        guard let existing = habits.first(where: { $0.id == id }) else { return }

        let newName: String
        if let name = name {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && trimmed.count <= 100 {
                newName = trimmed
            } else {
                newName = existing.name
            }
        } else {
            newName = existing.name
        }

        let updated = Habit(
            id: existing.id,
            name: newName,
            description: description ?? existing.description,
            createdAt: existing.createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt ?? existing.deletedAt,
            frequency: frequency ?? existing.frequency,
            difficultyTier: difficultyTier ?? existing.difficultyTier,
            durationSeconds: durationSeconds ?? existing.durationSeconds,
            lockoutDurationSeconds: lockoutDurationSeconds ?? existing.lockoutDurationSeconds,
            skipConsequence: skipConsequence ?? existing.skipConsequence
        )

        upsert(updated, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(ids: [id])
        }
    }

    func mergeHabits(_ remoteHabits: [Habit]) {
        guard !remoteHabits.isEmpty else { return }
        let merged = OwnerScopedRecordSupport.mergeRecords(local: habits, remote: remoteHabits)
        replaceHabits(merged)
    }

    func replaceHabits(_ authoritativeHabits: [Habit]) {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeHabits)
        do {
            try persistReplacedHabits(sorted)
        } catch {
            assertionFailure("Failed to replace habits: \(error)")
            return
        }
    }

    func getDirtyHabits(ids: Set<RecordID>) -> [Habit] {
        habits.filter { ids.contains($0.id) }
    }

    func purgeDeletedHabits(excluding dirtyIDs: Set<RecordID> = []) {
        do {
            try persistDeletedHabitPurge(excluding: dirtyIDs)
        } catch {
            assertionFailure("Failed to purge deleted habits: \(error)")
            return
        }
    }

    func allHabitIDs() -> [RecordID] {
        habits.map(\.id)
    }

    func migrateHabits(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> [RecordID] {
        guard sourceOwnerID != destinationOwnerID else { return [] }
        let source = loadHabits(ownerID: sourceOwnerID)
        let destination = loadHabits(ownerID: destinationOwnerID)
        let merged = OwnerScopedRecordSupport.mergeRecords(local: destination, remote: source)

        try replaceRows(ownerID: destinationOwnerID, habits: merged, on: databaseHandle)
        try replaceRows(ownerID: sourceOwnerID, habits: [], on: databaseHandle)
        return source.map(\.id)
    }

    func persistReplacedHabits(_ authoritativeHabits: [Habit]) throws {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeHabits)
        try database.transaction(at: databaseURL) { db in
            try self.replaceRows(ownerID: self.currentOwnerID, habits: sorted, on: db)
        }
        habits = sorted
    }

    func replaceHabits(
        _ authoritativeHabits: [Habit],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeHabits)
        try replaceRows(ownerID: currentOwnerID, habits: sorted, on: databaseHandle)
    }

    func persistDeletedHabitPurge(excluding dirtyIDs: Set<RecordID>) throws {
        try database.transaction(at: databaseURL) { db in
            try self.purgeDeletedHabits(excluding: dirtyIDs, on: db)
        }
        refreshCurrentHabits()
    }

    func purgeDeletedHabits(
        excluding dirtyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        if dirtyIDs.isEmpty {
            try database.execute(
                "DELETE FROM habits WHERE owner_id = ? AND deleted_at IS NOT NULL",
                bindings: [.text(currentOwnerID)],
                on: databaseHandle
            )
            return
        }

        let placeholders = Array(repeating: "?", count: dirtyIDs.count).joined(separator: ", ")
        let bindings = [.text(currentOwnerID)] + dirtyIDs.sorted { $0.rawValue < $1.rawValue }.map { .text($0.rawValue) }
        try database.execute(
            "DELETE FROM habits WHERE owner_id = ? AND deleted_at IS NOT NULL AND id NOT IN (\(placeholders))",
            bindings: bindings,
            on: databaseHandle
        )
    }

    private func upsert(_ habit: Habit, markDirty: Bool) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.upsert(habit, on: db)
                if markDirty, self.currentOwnerID != StorageOwner.local {
                    try self.syncStateStore.markDirty(userID: self.currentOwnerID, kind: .habits, ids: [habit.id], on: db)
                }
            }
        } catch {
            assertionFailure("Failed to upsert habit: \(error)")
            return
        }
        refreshCurrentHabits()
    }

    private func upsert(_ habit: Habit, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO habits (
                id, owner_id, name, description, created_at, updated_at, deleted_at,
                min_daily_frequency, difficulty_tier, duration_seconds,
                lockout_duration_seconds, skip_consequence
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                owner_id = excluded.owner_id,
                name = excluded.name,
                description = excluded.description,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                min_daily_frequency = excluded.min_daily_frequency,
                difficulty_tier = excluded.difficulty_tier,
                duration_seconds = excluded.duration_seconds,
                lockout_duration_seconds = excluded.lockout_duration_seconds,
                skip_consequence = excluded.skip_consequence
            """,
            bindings: habitBindings(habit, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func loadHabits(ownerID: String) -> [Habit] {
        let fetched = (try? database.query(
            """
            SELECT id, name, description, created_at, updated_at, deleted_at,
                   min_daily_frequency, difficulty_tier, duration_seconds,
                   lockout_duration_seconds, skip_consequence
            FROM habits
            WHERE owner_id = ?
            ORDER BY created_at ASC, id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            Habit(
                id: RecordID(SQLiteColumn.text(row, index: 0)),
                name: SQLiteColumn.text(row, index: 1),
                description: SQLiteColumn.text(row, index: 2),
                createdAt: SQLiteColumn.date(row, index: 3),
                updatedAt: SQLiteColumn.date(row, index: 4),
                deletedAt: SQLiteColumn.optionalDate(row, index: 5),
                frequency: SQLiteColumn.optionalDouble(row, index: 6),
                difficultyTier: SQLiteColumn.optionalText(row, index: 7).flatMap(HabitDifficultyTier.init(rawValue:)),
                durationSeconds: SQLiteColumn.optionalInt(row, index: 8),
                lockoutDurationSeconds: SQLiteColumn.optionalInt(row, index: 9),
                skipConsequence: SQLiteColumn.optionalInt(row, index: 10)
            )
        }) ?? []

        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func refreshCurrentHabits() {
        habits = loadHabits(ownerID: currentOwnerID)
    }

    private func replaceRows(ownerID: String, habits: [Habit], on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            "DELETE FROM habits WHERE owner_id = ?",
            bindings: [.text(ownerID)],
            on: databaseHandle
        )

        for habit in habits {
            try database.execute(
                """
                INSERT INTO habits (
                    id, owner_id, name, description, created_at, updated_at, deleted_at,
                    min_daily_frequency, difficulty_tier, duration_seconds,
                    lockout_duration_seconds, skip_consequence
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: habitBindings(habit, ownerID: ownerID),
                on: databaseHandle
            )
        }
    }

    private func habitBindings(_ habit: Habit, ownerID: String) -> [SQLiteValue] {
        [
            .text(habit.id.rawValue),
            .text(ownerID),
            .text(habit.name),
            .text(habit.description),
            .double(habit.createdAt.timeIntervalSince1970),
            .double(habit.updatedAt.timeIntervalSince1970),
            habit.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            habit.frequency.map(SQLiteValue.double) ?? .null,
            habit.difficultyTier.map { .text($0.rawValue) } ?? .null,
            habit.durationSeconds.map { .int(Int64($0)) } ?? .null,
            habit.lockoutDurationSeconds.map { .int(Int64($0)) } ?? .null,
            habit.skipConsequence.map { .int(Int64($0)) } ?? .null
        ]
    }

    private func notifySync(ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .habits, recordIDs: ids))
    }
}
