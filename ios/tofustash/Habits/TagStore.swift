import Foundation

enum EntityListTagScope {
    case habits
    case rewards
}

@Observable
@MainActor
final class TagStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore

    private(set) var currentOwnerID: String
    private(set) var tags: [Tag] = []
    private(set) var habitTags: [HabitTag] = []
    private(set) var rewardTags: [RewardTag] = []

    var activeTags: [Tag] {
        tags.filter { $0.deletedAt == nil }
    }

    var activeTagIDs: Set<RecordID> {
        Set(activeTags.map(\.id))
    }

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.syncStateStore = SyncStateStore(storageURL: self.databaseURL)
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        refreshAll()
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        refreshAll()
    }

    func migrateData(from sourceOwnerID: String, to destinationOwnerID: String) -> (tagIDs: [RecordID], habitTagIDs: [RecordID], rewardTagIDs: [RecordID]) {
        guard sourceOwnerID != destinationOwnerID else {
            return ([], [], [])
        }
        do {
            let result = try database.transaction(at: databaseURL) { db in
                try self.migrateData(from: sourceOwnerID, to: destinationOwnerID, on: db)
            }
            refreshAll()
            return result
        } catch {
            assertionFailure("Failed to migrate tag data: \(error)")
            return ([], [], [])
        }
    }

    @discardableResult
    func addTag(
        id: RecordID? = nil,
        name: String,
        colorHex: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) -> Tag? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let now = Date()
        let tag = Tag(
            id: id ?? RecordID(),
            name: trimmed,
            colorHex: colorHex ?? ColorGeneration.randomHexColor(),
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deletedAt: deletedAt
        )

        upsertTag(tag, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(kind: .tags, ids: [tag.id])
        }
        return tag
    }

    func updateTag(
        id: RecordID,
        name: String? = nil,
        colorHex: String? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date?? = nil,
        shouldNotifySync: Bool = true
    ) {
        guard let existing = tags.first(where: { $0.id == id }) else { return }

        let newName: String
        if let name = name {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            newName = trimmed
        } else {
            newName = existing.name
        }

        let updated = Tag(
            id: existing.id,
            name: newName,
            colorHex: colorHex ?? existing.colorHex,
            createdAt: existing.createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt ?? existing.deletedAt
        )

        upsertTag(updated, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(kind: .tags, ids: [id])
        }
    }

    func deleteTag(id: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        updateTag(id: id, updatedAt: deletedAt, deletedAt: .some(deletedAt), shouldNotifySync: shouldNotifySync)
    }

    func addTagToHabit(
        tagId: RecordID,
        habitId: RecordID,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        let now = Date()
        let association = HabitTag(
            habitId: habitId,
            tagId: tagId,
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deletedAt: deletedAt
        )

        upsertHabitTag(association, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(kind: .habitTags, ids: [association.id])
        }
    }

    func removeTagFromHabit(tagId: RecordID, habitId: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        guard let existing = habitTags.first(where: {
            $0.tagId == tagId && $0.habitId == habitId && $0.deletedAt == nil
        }) else { return }

        let deleted = HabitTag(
            habitId: existing.habitId,
            tagId: existing.tagId,
            createdAt: existing.createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt
        )

        upsertHabitTag(deleted, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(kind: .habitTags, ids: [deleted.id])
        }
    }

    func tagsForHabit(habitId: RecordID) -> [Tag] {
        let activeAssociationTagIDs = Set(
            habitTags
                .filter { $0.habitId == habitId && $0.deletedAt == nil }
                .map(\.tagId)
        )
        return activeTags.filter { activeAssociationTagIDs.contains($0.id) }
    }

    func addTagToReward(
        tagId: RecordID,
        rewardId: RecordID,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        let now = Date()
        let association = RewardTag(
            rewardId: rewardId,
            tagId: tagId,
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deletedAt: deletedAt
        )

        upsertRewardTag(association, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(kind: .rewardTags, ids: [association.id])
        }
    }

    func removeTagFromReward(tagId: RecordID, rewardId: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        guard let existing = rewardTags.first(where: {
            $0.tagId == tagId && $0.rewardId == rewardId && $0.deletedAt == nil
        }) else { return }

        let deleted = RewardTag(
            rewardId: existing.rewardId,
            tagId: existing.tagId,
            createdAt: existing.createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt
        )

        upsertRewardTag(deleted, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(kind: .rewardTags, ids: [deleted.id])
        }
    }

    func tagsForReward(rewardId: RecordID) -> [Tag] {
        let activeAssociationTagIDs = Set(
            rewardTags
                .filter { $0.rewardId == rewardId && $0.deletedAt == nil }
                .map(\.tagId)
        )
        return activeTags.filter { activeAssociationTagIDs.contains($0.id) }
    }

    func tags(for target: TagAssignmentTarget) -> [Tag] {
        switch target {
        case .habit(let habitId):
            return tagsForHabit(habitId: habitId)
        case .reward(let rewardId):
            return tagsForReward(rewardId: rewardId)
        }
    }

    func addTag(tagId: RecordID, to target: TagAssignmentTarget) {
        switch target {
        case .habit(let habitId):
            addTagToHabit(tagId: tagId, habitId: habitId)
        case .reward(let rewardId):
            addTagToReward(tagId: tagId, rewardId: rewardId)
        }
    }

    func removeTag(tagId: RecordID, from target: TagAssignmentTarget) {
        switch target {
        case .habit(let habitId):
            removeTagFromHabit(tagId: tagId, habitId: habitId)
        case .reward(let rewardId):
            removeTagFromReward(tagId: tagId, rewardId: rewardId)
        }
    }

    func mergeTags(_ remoteTags: [Tag]) {
        guard !remoteTags.isEmpty else { return }
        replaceAll(
            tags: OwnerScopedRecordSupport.mergeRecords(local: tags, remote: remoteTags),
            habitTags: habitTags,
            rewardTags: rewardTags
        )
    }

    func mergeHabitTags(_ remoteHabitTags: [HabitTag]) {
        guard !remoteHabitTags.isEmpty else { return }
        replaceAll(
            tags: tags,
            habitTags: OwnerScopedRecordSupport.mergeRecords(local: habitTags, remote: remoteHabitTags),
            rewardTags: rewardTags
        )
    }

    func mergeRewardTags(_ remoteRewardTags: [RewardTag]) {
        guard !remoteRewardTags.isEmpty else { return }
        replaceAll(
            tags: tags,
            habitTags: habitTags,
            rewardTags: OwnerScopedRecordSupport.mergeRecords(local: rewardTags, remote: remoteRewardTags)
        )
    }

    func replaceAll(
        tags authoritativeTags: [Tag],
        habitTags authoritativeHabitTags: [HabitTag],
        rewardTags authoritativeRewardTags: [RewardTag]
    ) {
        let sortedTags = OwnerScopedRecordSupport.sorted(authoritativeTags)
        let sortedHabitTags = OwnerScopedRecordSupport.sorted(authoritativeHabitTags)
        let sortedRewardTags = OwnerScopedRecordSupport.sorted(authoritativeRewardTags)

        do {
            try persistReplacedAll(tags: sortedTags, habitTags: sortedHabitTags, rewardTags: sortedRewardTags)
        } catch {
            assertionFailure("Failed to replace tag data: \(error)")
            return
        }
    }

    func getDirtyTags(ids: Set<RecordID>) -> [Tag] {
        tags.filter { ids.contains($0.id) }
    }

    func getDirtyHabitTags(ids: Set<RecordID>) -> [HabitTag] {
        habitTags.filter { ids.contains($0.id) }
    }

    func getDirtyRewardTags(ids: Set<RecordID>) -> [RewardTag] {
        rewardTags.filter { ids.contains($0.id) }
    }

    func purgeDeleted(
        excludingTagIDs dirtyTagIDs: Set<RecordID> = [],
        habitTagIDs dirtyHabitTagIDs: Set<RecordID> = [],
        rewardTagIDs dirtyRewardTagIDs: Set<RecordID> = []
    ) {
        do {
            try persistDeletedPurge(
                excludingTagIDs: dirtyTagIDs,
                habitTagIDs: dirtyHabitTagIDs,
                rewardTagIDs: dirtyRewardTagIDs
            )
        } catch {
            assertionFailure("Failed to purge deleted tag data: \(error)")
            return
        }
    }

    func allTagIDs() -> [RecordID] {
        tags.map(\.id)
    }

    func allHabitTagIDs() -> [RecordID] {
        habitTags.map(\.id)
    }

    func allRewardTagIDs() -> [RecordID] {
        rewardTags.map(\.id)
    }

    func migrateData(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> (tagIDs: [RecordID], habitTagIDs: [RecordID], rewardTagIDs: [RecordID]) {
        guard sourceOwnerID != destinationOwnerID else {
            return ([], [], [])
        }

        let sourceTags = loadTags(ownerID: sourceOwnerID)
        let sourceHabitTags = loadHabitTags(ownerID: sourceOwnerID)
        let sourceRewardTags = loadRewardTags(ownerID: sourceOwnerID)

        let destinationTags = loadTags(ownerID: destinationOwnerID)
        let destinationHabitTags = loadHabitTags(ownerID: destinationOwnerID)
        let destinationRewardTags = loadRewardTags(ownerID: destinationOwnerID)

        let mergedTags = OwnerScopedRecordSupport.mergeRecords(local: destinationTags, remote: sourceTags)
        let mergedHabitTags = OwnerScopedRecordSupport.mergeRecords(local: destinationHabitTags, remote: sourceHabitTags)
        let mergedRewardTags = OwnerScopedRecordSupport.mergeRecords(local: destinationRewardTags, remote: sourceRewardTags)

        try replaceTagRows(ownerID: destinationOwnerID, tags: mergedTags, on: databaseHandle)
        try replaceHabitTagRows(ownerID: destinationOwnerID, rows: mergedHabitTags, on: databaseHandle)
        try replaceRewardTagRows(ownerID: destinationOwnerID, rows: mergedRewardTags, on: databaseHandle)

        try replaceTagRows(ownerID: sourceOwnerID, tags: [], on: databaseHandle)
        try replaceHabitTagRows(ownerID: sourceOwnerID, rows: [], on: databaseHandle)
        try replaceRewardTagRows(ownerID: sourceOwnerID, rows: [], on: databaseHandle)

        return (
            sourceTags.map(\.id),
            sourceHabitTags.map(\.id),
            sourceRewardTags.map(\.id)
        )
    }

    func persistReplacedAll(
        tags authoritativeTags: [Tag],
        habitTags authoritativeHabitTags: [HabitTag],
        rewardTags authoritativeRewardTags: [RewardTag]
    ) throws {
        let sortedTags = OwnerScopedRecordSupport.sorted(authoritativeTags)
        let sortedHabitTags = OwnerScopedRecordSupport.sorted(authoritativeHabitTags)
        let sortedRewardTags = OwnerScopedRecordSupport.sorted(authoritativeRewardTags)

        try database.transaction(at: databaseURL) { db in
            try self.replaceTagRows(ownerID: self.currentOwnerID, tags: sortedTags, on: db)
            try self.replaceHabitTagRows(ownerID: self.currentOwnerID, rows: sortedHabitTags, on: db)
            try self.replaceRewardTagRows(ownerID: self.currentOwnerID, rows: sortedRewardTags, on: db)
        }

        tags = sortedTags
        habitTags = sortedHabitTags
        rewardTags = sortedRewardTags
    }

    func replaceAll(
        tags authoritativeTags: [Tag],
        habitTags authoritativeHabitTags: [HabitTag],
        rewardTags authoritativeRewardTags: [RewardTag],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try replaceTagRows(ownerID: currentOwnerID, tags: OwnerScopedRecordSupport.sorted(authoritativeTags), on: databaseHandle)
        try replaceHabitTagRows(ownerID: currentOwnerID, rows: OwnerScopedRecordSupport.sorted(authoritativeHabitTags), on: databaseHandle)
        try replaceRewardTagRows(ownerID: currentOwnerID, rows: OwnerScopedRecordSupport.sorted(authoritativeRewardTags), on: databaseHandle)
    }

    func persistDeletedPurge(
        excludingTagIDs dirtyTagIDs: Set<RecordID>,
        habitTagIDs dirtyHabitTagIDs: Set<RecordID>,
        rewardTagIDs dirtyRewardTagIDs: Set<RecordID>
    ) throws {
        try database.transaction(at: databaseURL) { db in
            try self.purgeDeleted(
                excludingTagIDs: dirtyTagIDs,
                habitTagIDs: dirtyHabitTagIDs,
                rewardTagIDs: dirtyRewardTagIDs,
                on: db
            )
        }
        refreshAll()
    }

    func purgeDeleted(
        excludingTagIDs dirtyTagIDs: Set<RecordID>,
        habitTagIDs dirtyHabitTagIDs: Set<RecordID>,
        rewardTagIDs dirtyRewardTagIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try purgeDeletedTags(dirtyTagIDs, on: databaseHandle)
        try purgeDeletedHabitTags(dirtyHabitTagIDs, on: databaseHandle)
        try purgeDeletedRewardTags(dirtyRewardTagIDs, on: databaseHandle)
    }

    private func upsertTag(_ tag: Tag, markDirty: Bool) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.upsertTag(tag, on: db)
                if markDirty, self.currentOwnerID != StorageOwner.local {
                    try self.syncStateStore.markDirty(userID: self.currentOwnerID, kind: .tags, ids: [tag.id], on: db)
                }
            }
        } catch {
            assertionFailure("Failed to upsert tag: \(error)")
            return
        }
        refreshAll()
    }

    private func upsertHabitTag(_ row: HabitTag, markDirty: Bool) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.upsertHabitTag(row, on: db)
                if markDirty, self.currentOwnerID != StorageOwner.local {
                    try self.syncStateStore.markDirty(userID: self.currentOwnerID, kind: .habitTags, ids: [row.id], on: db)
                }
            }
        } catch {
            assertionFailure("Failed to upsert habit tag: \(error)")
            return
        }
        refreshAll()
    }

    private func upsertRewardTag(_ row: RewardTag, markDirty: Bool) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.upsertRewardTag(row, on: db)
                if markDirty, self.currentOwnerID != StorageOwner.local {
                    try self.syncStateStore.markDirty(userID: self.currentOwnerID, kind: .rewardTags, ids: [row.id], on: db)
                }
            }
        } catch {
            assertionFailure("Failed to upsert reward tag: \(error)")
            return
        }
        refreshAll()
    }

    private func upsertTag(_ tag: Tag, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO tags (id, owner_id, name, color_hex, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                owner_id = excluded.owner_id,
                name = excluded.name,
                color_hex = excluded.color_hex,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at
            """,
            bindings: tagBindings(tag, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func upsertHabitTag(_ row: HabitTag, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO habit_tags (owner_id, habit_id, tag_id, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_id, habit_id, tag_id) DO UPDATE SET
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at
            """,
            bindings: habitTagBindings(row, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func upsertRewardTag(_ row: RewardTag, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO reward_tags (owner_id, reward_id, tag_id, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_id, reward_id, tag_id) DO UPDATE SET
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at
            """,
            bindings: rewardTagBindings(row, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func loadTags(ownerID: String) -> [Tag] {
        let fetched = (try? database.query(
            """
            SELECT id, name, color_hex, created_at, updated_at, deleted_at
            FROM tags
            WHERE owner_id = ?
            ORDER BY created_at ASC, id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            Tag(
                id: RecordID(SQLiteColumn.text(row, index: 0)),
                name: SQLiteColumn.text(row, index: 1),
                colorHex: SQLiteColumn.text(row, index: 2),
                createdAt: SQLiteColumn.date(row, index: 3),
                updatedAt: SQLiteColumn.date(row, index: 4),
                deletedAt: SQLiteColumn.optionalDate(row, index: 5)
            )
        }) ?? []
        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func loadHabitTags(ownerID: String) -> [HabitTag] {
        let fetched = (try? database.query(
            """
            SELECT habit_id, tag_id, created_at, updated_at, deleted_at
            FROM habit_tags
            WHERE owner_id = ?
            ORDER BY created_at ASC, habit_id ASC, tag_id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            HabitTag(
                habitId: RecordID(SQLiteColumn.text(row, index: 0)),
                tagId: RecordID(SQLiteColumn.text(row, index: 1)),
                createdAt: SQLiteColumn.date(row, index: 2),
                updatedAt: SQLiteColumn.date(row, index: 3),
                deletedAt: SQLiteColumn.optionalDate(row, index: 4)
            )
        }) ?? []
        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func loadRewardTags(ownerID: String) -> [RewardTag] {
        let fetched = (try? database.query(
            """
            SELECT reward_id, tag_id, created_at, updated_at, deleted_at
            FROM reward_tags
            WHERE owner_id = ?
            ORDER BY created_at ASC, reward_id ASC, tag_id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            RewardTag(
                rewardId: RecordID(SQLiteColumn.text(row, index: 0)),
                tagId: RecordID(SQLiteColumn.text(row, index: 1)),
                createdAt: SQLiteColumn.date(row, index: 2),
                updatedAt: SQLiteColumn.date(row, index: 3),
                deletedAt: SQLiteColumn.optionalDate(row, index: 4)
            )
        }) ?? []
        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func refreshAll() {
        tags = loadTags(ownerID: currentOwnerID)
        habitTags = loadHabitTags(ownerID: currentOwnerID)
        rewardTags = loadRewardTags(ownerID: currentOwnerID)
    }

    private func replaceTagRows(ownerID: String, tags: [Tag], on databaseHandle: AppDatabaseHandle) throws {
        try database.execute("DELETE FROM tags WHERE owner_id = ?", bindings: [.text(ownerID)], on: databaseHandle)
        for tag in tags {
            try database.execute(
                """
                INSERT INTO tags (id, owner_id, name, color_hex, created_at, updated_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: tagBindings(tag, ownerID: ownerID),
                on: databaseHandle
            )
        }
    }

    private func replaceHabitTagRows(ownerID: String, rows: [HabitTag], on databaseHandle: AppDatabaseHandle) throws {
        try database.execute("DELETE FROM habit_tags WHERE owner_id = ?", bindings: [.text(ownerID)], on: databaseHandle)
        for row in rows {
            try database.execute(
                """
                INSERT INTO habit_tags (owner_id, habit_id, tag_id, created_at, updated_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                bindings: habitTagBindings(row, ownerID: ownerID),
                on: databaseHandle
            )
        }
    }

    private func replaceRewardTagRows(ownerID: String, rows: [RewardTag], on databaseHandle: AppDatabaseHandle) throws {
        try database.execute("DELETE FROM reward_tags WHERE owner_id = ?", bindings: [.text(ownerID)], on: databaseHandle)
        for row in rows {
            try database.execute(
                """
                INSERT INTO reward_tags (owner_id, reward_id, tag_id, created_at, updated_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                bindings: rewardTagBindings(row, ownerID: ownerID),
                on: databaseHandle
            )
        }
    }

    private func purgeDeletedTags(_ dirtyTagIDs: Set<RecordID>, on databaseHandle: AppDatabaseHandle) throws {
        if dirtyTagIDs.isEmpty {
            try database.execute("DELETE FROM tags WHERE owner_id = ? AND deleted_at IS NOT NULL", bindings: [.text(currentOwnerID)], on: databaseHandle)
            return
        }

        let placeholders = Array(repeating: "?", count: dirtyTagIDs.count).joined(separator: ", ")
        let bindings = [.text(currentOwnerID)] + dirtyTagIDs.sorted { $0.rawValue < $1.rawValue }.map { .text($0.rawValue) }
        try database.execute(
            "DELETE FROM tags WHERE owner_id = ? AND deleted_at IS NOT NULL AND id NOT IN (\(placeholders))",
            bindings: bindings,
            on: databaseHandle
        )
    }

    private func purgeDeletedHabitTags(_ dirtyHabitTagIDs: Set<RecordID>, on databaseHandle: AppDatabaseHandle) throws {
        try purgeDeletedAssociations(
            tableName: "habit_tags",
            keyColumnA: "habit_id",
            keyColumnB: "tag_id",
            dirtyIDs: dirtyHabitTagIDs,
            on: databaseHandle
        )
    }

    private func purgeDeletedRewardTags(_ dirtyRewardTagIDs: Set<RecordID>, on databaseHandle: AppDatabaseHandle) throws {
        try purgeDeletedAssociations(
            tableName: "reward_tags",
            keyColumnA: "reward_id",
            keyColumnB: "tag_id",
            dirtyIDs: dirtyRewardTagIDs,
            on: databaseHandle
        )
    }

    private func purgeDeletedAssociations(
        tableName: String,
        keyColumnA: String,
        keyColumnB: String,
        dirtyIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        if dirtyIDs.isEmpty {
            try database.execute(
                "DELETE FROM \(tableName) WHERE owner_id = ? AND deleted_at IS NOT NULL",
                bindings: [.text(currentOwnerID)],
                on: databaseHandle
            )
            return
        }

        let excludedClauses = dirtyIDs
            .sorted { $0.rawValue < $1.rawValue }
            .map { id -> [SQLiteValue] in
                let parts = id.rawValue.split(separator: ":").map(String.init)
                return [.text(parts[0]), .text(parts[1])]
            }

        var sql = "DELETE FROM \(tableName) WHERE owner_id = ? AND deleted_at IS NOT NULL"
        var bindings: [SQLiteValue] = [.text(currentOwnerID)]

        for pair in excludedClauses {
            sql += " AND NOT (\(keyColumnA) = ? AND \(keyColumnB) = ?)"
            bindings.append(contentsOf: pair)
        }

        try database.execute(sql, bindings: bindings, on: databaseHandle)
    }

    private func tagBindings(_ tag: Tag, ownerID: String) -> [SQLiteValue] {
        [
            .text(tag.id.rawValue),
            .text(ownerID),
            .text(tag.name),
            .text(tag.colorHex),
            .double(tag.createdAt.timeIntervalSince1970),
            .double(tag.updatedAt.timeIntervalSince1970),
            tag.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null
        ]
    }

    private func habitTagBindings(_ row: HabitTag, ownerID: String) -> [SQLiteValue] {
        [
            .text(ownerID),
            .text(row.habitId.rawValue),
            .text(row.tagId.rawValue),
            .double(row.createdAt.timeIntervalSince1970),
            .double(row.updatedAt.timeIntervalSince1970),
            row.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null
        ]
    }

    private func rewardTagBindings(_ row: RewardTag, ownerID: String) -> [SQLiteValue] {
        [
            .text(ownerID),
            .text(row.rewardId.rawValue),
            .text(row.tagId.rawValue),
            .double(row.createdAt.timeIntervalSince1970),
            .double(row.updatedAt.timeIntervalSince1970),
            row.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null
        ]
    }

    private func notifySync(kind: SyncEntityKind, ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: kind, recordIDs: ids))
    }
}
