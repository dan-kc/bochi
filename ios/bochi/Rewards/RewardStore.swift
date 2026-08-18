import Foundation

// Sync flow: signed-in reward edits mark records dirty and publish mutations;
// server replacements refresh the store without enqueueing another sync.
@Observable
@MainActor
final class RewardStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore

    private(set) var currentOwnerID: String
    private(set) var rewards: [Reward] = []

    var activeRewards: [Reward] {
        rewards.filter { $0.deletedAt == nil }
    }

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.syncStateStore = SyncStateStore(storageURL: self.databaseURL)
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        self.rewards = loadRewards(ownerID: initialOwnerID)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        rewards = loadRewards(ownerID: ownerID)
    }

    func migrateRewards(from sourceOwnerID: String, to destinationOwnerID: String) -> [RecordID] {
        guard sourceOwnerID != destinationOwnerID else { return [] }
        do {
            let migratedIDs = try database.transaction(at: databaseURL) { db in
                try self.migrateRewards(from: sourceOwnerID, to: destinationOwnerID, on: db)
            }
            refreshCurrentRewards()
            return migratedIDs
        } catch {
            assertionFailure("Failed to migrate rewards: \(error)")
            return []
        }
    }

    @discardableResult
    func addReward(
        id: RecordID? = nil,
        recurring: Bool = true,
        name: String,
        description: String = "",
        maxFrequency: Double? = nil,
        lockoutDurationSeconds: Int? = nil,
        basePrice: Int = 500,
        pinned: Bool = false,
        hidden: Bool = false,
        timerSelection: EntityTimerSelection = .none,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) -> Reward? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else {
            return nil
        }
        let canonicalID = id ?? RecordID()
        let now = Date()
        let reward = Reward(
            id: canonicalID,
            recurring: recurring,
            name: trimmedName,
            description: description,
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deletedAt: deletedAt,
            maxFrequency: maxFrequency,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: max(0, basePrice),
            pinned: pinned,
            hidden: hidden,
            timerSelection: timerSelection
        )

        upsert(reward, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(ids: [reward.id])
        }
        return reward
    }

    func updateReward(
        id: RecordID,
        name: String? = nil,
        description: String? = nil,
        maxFrequency: Double?? = nil,
        lockoutDurationSeconds: Int?? = nil,
        basePrice: Int? = nil,
        pinned: Bool? = nil,
        hidden: Bool? = nil,
        timerSelection: EntityTimerSelection? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date?? = nil,
        shouldNotifySync: Bool = true
    ) {
        guard let existing = rewards.first(where: { $0.id == id }) else { return }

        let newName: String
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && trimmed.count <= 100 {
                newName = trimmed
            } else {
                newName = existing.name
            }
        } else {
            newName = existing.name
        }

        let updated = Reward(
            id: existing.id,
            recurring: existing.recurring,
            name: newName,
            description: description ?? existing.description,
            createdAt: existing.createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt ?? existing.deletedAt,
            maxFrequency: maxFrequency ?? existing.maxFrequency,
            lockoutDurationSeconds: lockoutDurationSeconds ?? existing.lockoutDurationSeconds,
            basePrice: basePrice.map { max(0, $0) } ?? existing.basePrice,
            pinned: pinned ?? existing.pinned,
            hidden: hidden ?? existing.hidden,
            timerSelection: timerSelection ?? existing.timerSelection,
            serverRevision: existing.serverRevision
        )

        upsert(updated, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(ids: [id])
        }
    }

    func deleteReward(id: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        guard let existing = rewards.first(where: { $0.id == id }) else { return }
        let deleted = Reward(
            id: existing.id,
            recurring: existing.recurring,
            name: existing.name,
            description: existing.description,
            createdAt: existing.createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt,
            maxFrequency: existing.maxFrequency,
            lockoutDurationSeconds: existing.lockoutDurationSeconds,
            basePrice: existing.basePrice,
            pinned: existing.pinned,
            hidden: existing.hidden,
            timerSelection: existing.timerSelection,
            serverRevision: existing.serverRevision
        )
        upsert(deleted, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(ids: [id])
        }
    }

    func setPinned(id: RecordID, pinned: Bool, updatedAt: Date = Date(), shouldNotifySync: Bool = true) {
        updateReward(
            id: id,
            pinned: pinned,
            updatedAt: updatedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func setHidden(id: RecordID, hidden: Bool, updatedAt: Date = Date(), shouldNotifySync: Bool = true) {
        updateReward(
            id: id,
            hidden: hidden,
            updatedAt: updatedAt,
            shouldNotifySync: shouldNotifySync
        )
    }

    func mergeRewards(_ remoteRewards: [Reward]) {
        guard !remoteRewards.isEmpty else { return }
        replaceRewards(OwnerScopedRecordSupport.mergeRecords(local: rewards, remote: remoteRewards))
    }

    func replaceRewards(_ authoritativeRewards: [Reward]) {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeRewards)
        do {
            try persistReplacedRewards(sorted)
        } catch {
            assertionFailure("Failed to replace rewards: \(error)")
            return
        }
    }

    func getDirtyRewards(ids: Set<RecordID>) -> [Reward] {
        rewards.filter { ids.contains($0.id) }
    }

    func purgeDeletedRewards(excluding dirtyIDs: Set<RecordID> = []) {
        do {
            try persistDeletedRewardPurge(excluding: dirtyIDs)
        } catch {
            assertionFailure("Failed to purge deleted rewards: \(error)")
            return
        }
    }

    func allRewardIDs() -> [RecordID] {
        rewards.map(\.id)
    }

    func migrateRewards(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> [RecordID] {
        guard sourceOwnerID != destinationOwnerID else { return [] }
        let source = loadRewards(ownerID: sourceOwnerID)
        let destination = loadRewards(ownerID: destinationOwnerID)
        let merged = OwnerScopedRecordSupport.mergeRecords(local: destination, remote: source)

        // Remove the local-owner rows before re-inserting the merged account view
        // so a sign-in migration does not trip the global reward-id uniqueness rule.
        try replaceRows(ownerID: sourceOwnerID, rewards: [], on: databaseHandle)
        try replaceRows(ownerID: destinationOwnerID, rewards: merged, on: databaseHandle)
        return source.map(\.id)
    }

    func persistReplacedRewards(_ authoritativeRewards: [Reward]) throws {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeRewards)
        try database.transaction(at: databaseURL) { db in
            try self.replaceRows(ownerID: self.currentOwnerID, rewards: sorted, on: db)
        }
        rewards = sorted
    }

    func replaceRewards(
        _ authoritativeRewards: [Reward],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try replaceRows(
            ownerID: currentOwnerID,
            rewards: OwnerScopedRecordSupport.sorted(authoritativeRewards),
            on: databaseHandle
        )
    }

    func persistDeletedRewardPurge(excluding dirtyIDs: Set<RecordID>) throws {
        try database.transaction(at: databaseURL) { db in
            try self.purgeDeletedRewards(excluding: dirtyIDs, on: db)
        }
        refreshCurrentRewards()
    }

    func purgeDeletedRewards(
        excluding dirtyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        if dirtyIDs.isEmpty {
            try database.execute(
                "DELETE FROM rewards WHERE owner_id = ? AND deleted_at IS NOT NULL",
                bindings: [.text(currentOwnerID)],
                on: databaseHandle
            )
            return
        }

        let placeholders = Array(repeating: "?", count: dirtyIDs.count).joined(separator: ", ")
        let bindings: [SQLiteValue] = [SQLiteValue.text(currentOwnerID)]
            + dirtyIDs.sorted { $0.rawValue < $1.rawValue }.map { SQLiteValue.text($0.rawValue) }
        try database.execute(
            "DELETE FROM rewards WHERE owner_id = ? AND deleted_at IS NOT NULL AND id NOT IN (\(placeholders))",
            bindings: bindings,
            on: databaseHandle
        )
    }

    private func upsert(_ reward: Reward, markDirty: Bool) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.upsert(reward, on: db)
                if markDirty, self.currentOwnerID != StorageOwner.local {
                    try self.syncStateStore.markDirty(userID: self.currentOwnerID, kind: .rewards, ids: [reward.id], on: db)
                }
            }
        } catch {
            assertionFailure("Failed to upsert reward: \(error)")
            return
        }
        refreshCurrentRewards()
    }

    private func upsert(_ reward: Reward, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO rewards (
                id, owner_id, name, description, created_at, updated_at, deleted_at,
                recurring, max_daily_frequency, base_price, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                owner_id = excluded.owner_id,
                recurring = excluded.recurring,
                name = excluded.name,
                description = excluded.description,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                max_daily_frequency = excluded.max_daily_frequency,
                base_price = excluded.base_price,
                lockout_duration_seconds = excluded.lockout_duration_seconds,
                pinned = excluded.pinned,
                hidden = excluded.hidden,
                timer_mode = excluded.timer_mode,
                timer_id = excluded.timer_id,
                server_revision = excluded.server_revision
            """,
            bindings: rewardBindings(reward, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func upsert(_ reward: Reward, ownerID: String, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO rewards (
                id, owner_id, name, description, created_at, updated_at, deleted_at,
                recurring, max_daily_frequency, base_price, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                owner_id = excluded.owner_id,
                recurring = excluded.recurring,
                name = excluded.name,
                description = excluded.description,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                max_daily_frequency = excluded.max_daily_frequency,
                base_price = excluded.base_price,
                lockout_duration_seconds = excluded.lockout_duration_seconds,
                pinned = excluded.pinned,
                hidden = excluded.hidden,
                timer_mode = excluded.timer_mode,
                timer_id = excluded.timer_id,
                server_revision = excluded.server_revision
            """,
            bindings: rewardBindings(reward, ownerID: ownerID),
            on: databaseHandle
        )
    }

    private func loadRewards(ownerID: String) -> [Reward] {
        let fetched = (try? database.query(
           """
            SELECT id, name, description, created_at, updated_at, deleted_at,
                   recurring, max_daily_frequency, base_price, lockout_duration_seconds, pinned, hidden, timer_mode, timer_id, server_revision
            FROM rewards
            WHERE owner_id = ?
            ORDER BY created_at ASC, id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            Reward(
                id: RecordID(SQLiteColumn.text(row, index: 0)),
                recurring: SQLiteColumn.bool(row, index: 6),
                name: SQLiteColumn.text(row, index: 1),
                description: SQLiteColumn.text(row, index: 2),
                createdAt: SQLiteColumn.date(row, index: 3),
                updatedAt: SQLiteColumn.date(row, index: 4),
                deletedAt: SQLiteColumn.optionalDate(row, index: 5),
                maxFrequency: SQLiteColumn.optionalDouble(row, index: 7),
                lockoutDurationSeconds: SQLiteColumn.optionalInt(row, index: 9),
                basePrice: SQLiteColumn.int(row, index: 8),
                pinned: SQLiteColumn.bool(row, index: 10),
                hidden: SQLiteColumn.bool(row, index: 11),
                timerSelection: EntityTimerSelection.from(
                    mode: SQLiteColumn.optionalText(row, index: 12),
                    timerID: SQLiteColumn.optionalText(row, index: 13).map { RecordID($0) }
                ),
                serverRevision: SQLiteColumn.optionalInt64(row, index: 14)
            )
        }) ?? []

        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func refreshCurrentRewards() {
        rewards = loadRewards(ownerID: currentOwnerID)
    }

    private func replaceRows(ownerID: String, rewards: [Reward], on databaseHandle: AppDatabaseHandle) throws {
        // Full sync gives us an authoritative owner snapshot. Delete only rows
        // missing from that snapshot, then upsert changed/current rows.
        try database.execute(
            "CREATE TEMP TABLE IF NOT EXISTS reward_replacement_ids (id TEXT PRIMARY KEY)",
            on: databaseHandle
        )
        try database.execute(
            "DELETE FROM reward_replacement_ids",
            on: databaseHandle
        )
        for reward in rewards {
            try database.execute(
                "INSERT OR IGNORE INTO reward_replacement_ids (id) VALUES (?)",
                bindings: [.text(reward.id.rawValue)],
                on: databaseHandle
            )
        }
        try database.execute(
            """
            DELETE FROM rewards
            WHERE owner_id = ?
              AND NOT EXISTS (
                  SELECT 1 FROM reward_replacement_ids replacement
                  WHERE replacement.id = rewards.id
              )
            """,
            bindings: [.text(ownerID)],
            on: databaseHandle
        )

        for reward in rewards {
            try upsert(reward, ownerID: ownerID, on: databaseHandle)
        }
        try database.execute("DELETE FROM reward_replacement_ids", on: databaseHandle)
    }

    private func rewardBindings(_ reward: Reward, ownerID: String) -> [SQLiteValue] {
        [
            .text(reward.id.rawValue),
            .text(ownerID),
            .text(reward.name),
            .text(reward.description),
            .double(reward.createdAt.timeIntervalSince1970),
            .double(reward.updatedAt.timeIntervalSince1970),
            reward.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            .int(reward.recurring ? 1 : 0),
            reward.maxFrequency.map(SQLiteValue.double) ?? .null,
            .int(Int64(reward.basePrice)),
            reward.lockoutDurationSeconds.map { .int(Int64($0)) } ?? .null,
            .int(reward.pinned ? 1 : 0),
            .int(reward.hidden ? 1 : 0),
            reward.timerSelection.modeValue.map { .text($0) } ?? .null,
            reward.timerSelection.timerID.map { .text($0.rawValue) } ?? .null,
            reward.serverRevision.map { .int($0) } ?? .null
        ]
    }

    private func notifySync(ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .rewards, recordIDs: ids))
    }
}
