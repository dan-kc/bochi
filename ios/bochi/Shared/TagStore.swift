import Foundation

// Sync flow: tag and tag-link edits mark the active account dirty and publish
// mutations; sync applies authoritative tag snapshots through replacement APIs.
enum EntityListTagScope {
    case search
    case earn
    case tasks
    case recurringTasks
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
    private(set) var taskTags: [TaskTag] = []
    private(set) var recurringTaskTags: [RecurringTaskTag] = []
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

    func migrateData(from sourceOwnerID: String, to destinationOwnerID: String) -> (tagIDs: [RecordID], taskTagIDs: [RecordID], recurringTaskTagIDs: [RecordID], rewardTagIDs: [RecordID]) {
        guard sourceOwnerID != destinationOwnerID else {
            return ([], [], [], [])
        }
        do {
            let result = try database.transaction(at: databaseURL) { db in
                try self.migrateData(from: sourceOwnerID, to: destinationOwnerID, on: db)
            }
            refreshAll()
            return result
        } catch {
            assertionFailure("Failed to migrate tag data: \(error)")
            return ([], [], [], [])
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
            deletedAt: deletedAt ?? existing.deletedAt,
            serverRevision: existing.serverRevision
        )

        upsertTag(updated, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(kind: .tags, ids: [id])
        }
    }

    func deleteTag(id: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        updateTag(id: id, updatedAt: deletedAt, deletedAt: .some(deletedAt), shouldNotifySync: shouldNotifySync)
    }

    func addTagToRecurringTask(
        tagId: RecordID,
        recurringTaskId: RecordID,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        let now = Date()
        let existing = recurringTaskTags.first { $0.recurringTaskId == recurringTaskId && $0.tagId == tagId }
        let association = RecurringTaskTag(
            recurringTaskId: recurringTaskId,
            tagId: tagId,
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deletedAt: deletedAt,
            serverRevision: existing?.serverRevision
        )

        upsertRecurringTaskTag(association, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(kind: .recurringTaskTags, ids: [association.id])
        }
    }

    func addTagToTask(
        tagId: RecordID,
        taskId: RecordID,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) {
        let now = Date()
        let existing = taskTags.first { $0.taskId == taskId && $0.tagId == tagId }
        let association = TaskTag(
            taskId: taskId,
            tagId: tagId,
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deletedAt: deletedAt,
            serverRevision: existing?.serverRevision
        )

        upsertTaskTag(association, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(kind: .taskTags, ids: [association.id])
        }
    }

    func removeTagFromTask(tagId: RecordID, taskId: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        guard let existing = taskTags.first(where: {
            $0.tagId == tagId && $0.taskId == taskId && $0.deletedAt == nil
        }) else { return }

        let deleted = TaskTag(
            taskId: existing.taskId,
            tagId: existing.tagId,
            createdAt: existing.createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt,
            serverRevision: existing.serverRevision
        )

        upsertTaskTag(deleted, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(kind: .taskTags, ids: [deleted.id])
        }
    }

    func tagsForTask(taskId: RecordID) -> [Tag] {
        let activeAssociationTagIDs = Set(
            taskTags
                .filter { $0.taskId == taskId && $0.deletedAt == nil }
                .map(\.tagId)
        )
        let activeTagsByID = Dictionary(uniqueKeysWithValues: activeTags.map { ($0.id, $0) })
        return sortedTags(tagIDs: activeAssociationTagIDs, activeTagsByID: activeTagsByID)
    }

    func tagsByTaskID() -> [RecordID: [Tag]] {
        let activeTagsByID = Dictionary(uniqueKeysWithValues: activeTags.map { ($0.id, $0) })
        let activeAssociationTagIDsByTaskID = taskTags.reduce(into: [RecordID: Set<RecordID>]()) { result, taskTag in
            guard taskTag.deletedAt == nil else { return }
            result[taskTag.taskId, default: []].insert(taskTag.tagId)
        }

        return activeAssociationTagIDsByTaskID.mapValues { tagIDs in
            // List rows ask for tags grouped by entity; map tag IDs directly so
            // large tag lists are not rescanned for every task.
            sortedTags(tagIDs: tagIDs, activeTagsByID: activeTagsByID)
        }
    }

    func removeTagFromRecurringTask(tagId: RecordID, recurringTaskId: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        guard let existing = recurringTaskTags.first(where: {
            $0.tagId == tagId && $0.recurringTaskId == recurringTaskId && $0.deletedAt == nil
        }) else { return }

        let deleted = RecurringTaskTag(
            recurringTaskId: existing.recurringTaskId,
            tagId: existing.tagId,
            createdAt: existing.createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt,
            serverRevision: existing.serverRevision
        )

        upsertRecurringTaskTag(deleted, markDirty: shouldNotifySync)
        if shouldNotifySync {
            notifySync(kind: .recurringTaskTags, ids: [deleted.id])
        }
    }

    func tagsForRecurringTask(recurringTaskId: RecordID) -> [Tag] {
        let activeAssociationTagIDs = Set(
            recurringTaskTags
                .filter { $0.recurringTaskId == recurringTaskId && $0.deletedAt == nil }
                .map(\.tagId)
        )
        let activeTagsByID = Dictionary(uniqueKeysWithValues: activeTags.map { ($0.id, $0) })
        return sortedTags(tagIDs: activeAssociationTagIDs, activeTagsByID: activeTagsByID)
    }

    func tagsByRecurringTaskID() -> [RecordID: [Tag]] {
        let activeTagsByID = Dictionary(uniqueKeysWithValues: activeTags.map { ($0.id, $0) })
        let activeAssociationTagIDsByRecurringTaskID = recurringTaskTags.reduce(into: [RecordID: Set<RecordID>]()) { result, recurringTaskTag in
            guard recurringTaskTag.deletedAt == nil else { return }
            result[recurringTaskTag.recurringTaskId, default: []].insert(recurringTaskTag.tagId)
        }

        return activeAssociationTagIDsByRecurringTaskID.mapValues { tagIDs in
            // RecurringTask list/search rows should pay one dictionary lookup per tag,
            // not one full active-tag scan per recurringTask.
            sortedTags(tagIDs: tagIDs, activeTagsByID: activeTagsByID)
        }
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
        let existing = rewardTags.first { $0.rewardId == rewardId && $0.tagId == tagId }
        let association = RewardTag(
            rewardId: rewardId,
            tagId: tagId,
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deletedAt: deletedAt,
            serverRevision: existing?.serverRevision
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
            deletedAt: deletedAt,
            serverRevision: existing.serverRevision
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
        let activeTagsByID = Dictionary(uniqueKeysWithValues: activeTags.map { ($0.id, $0) })
        return sortedTags(tagIDs: activeAssociationTagIDs, activeTagsByID: activeTagsByID)
    }

    func tagsByRewardID() -> [RecordID: [Tag]] {
        let activeTagsByID = Dictionary(uniqueKeysWithValues: activeTags.map { ($0.id, $0) })
        let activeAssociationTagIDsByRewardID = rewardTags.reduce(into: [RecordID: Set<RecordID>]()) { result, rewardTag in
            guard rewardTag.deletedAt == nil else { return }
            result[rewardTag.rewardId, default: []].insert(rewardTag.tagId)
        }

        return activeAssociationTagIDsByRewardID.mapValues { tagIDs in
            // Reward rows use this for every visible row, so avoid repeated
            // active-tag scans as reward count grows.
            sortedTags(tagIDs: tagIDs, activeTagsByID: activeTagsByID)
        }
    }

    func tags(for target: TagAssignmentTarget) -> [Tag] {
        switch target {
        case .task(let taskId):
            return tagsForTask(taskId: taskId)
        case .recurringTask(let recurringTaskId):
            return tagsForRecurringTask(recurringTaskId: recurringTaskId)
        case .reward(let rewardId):
            return tagsForReward(rewardId: rewardId)
        }
    }

    func addTag(tagId: RecordID, to target: TagAssignmentTarget, shouldNotifySync: Bool = true) {
        switch target {
        case .task(let taskId):
            addTagToTask(tagId: tagId, taskId: taskId, shouldNotifySync: shouldNotifySync)
        case .recurringTask(let recurringTaskId):
            addTagToRecurringTask(tagId: tagId, recurringTaskId: recurringTaskId, shouldNotifySync: shouldNotifySync)
        case .reward(let rewardId):
            addTagToReward(tagId: tagId, rewardId: rewardId, shouldNotifySync: shouldNotifySync)
        }
    }

    func removeTag(tagId: RecordID, from target: TagAssignmentTarget, shouldNotifySync: Bool = true) {
        switch target {
        case .task(let taskId):
            removeTagFromTask(tagId: tagId, taskId: taskId, shouldNotifySync: shouldNotifySync)
        case .recurringTask(let recurringTaskId):
            removeTagFromRecurringTask(tagId: tagId, recurringTaskId: recurringTaskId, shouldNotifySync: shouldNotifySync)
        case .reward(let rewardId):
            removeTagFromReward(tagId: tagId, rewardId: rewardId, shouldNotifySync: shouldNotifySync)
        }
    }

    private func sortedTags(tagIDs: Set<RecordID>, activeTagsByID: [RecordID: Tag]) -> [Tag] {
        OwnerScopedRecordSupport.sorted(tagIDs.compactMap { activeTagsByID[$0] })
    }

    func mergeTags(_ remoteTags: [Tag]) {
        guard !remoteTags.isEmpty else { return }
        replaceAll(
            tags: OwnerScopedRecordSupport.mergeRecords(local: tags, remote: remoteTags),
            taskTags: taskTags,
            recurringTaskTags: recurringTaskTags,
            rewardTags: rewardTags
        )
    }

    func mergeTaskTags(_ remoteTaskTags: [TaskTag]) {
        guard !remoteTaskTags.isEmpty else { return }
        replaceAll(
            tags: tags,
            taskTags: OwnerScopedRecordSupport.mergeRecords(local: taskTags, remote: remoteTaskTags),
            recurringTaskTags: recurringTaskTags,
            rewardTags: rewardTags
        )
    }

    func mergeRecurringTaskTags(_ remoteRecurringTaskTags: [RecurringTaskTag]) {
        guard !remoteRecurringTaskTags.isEmpty else { return }
        replaceAll(
            tags: tags,
            taskTags: taskTags,
            recurringTaskTags: OwnerScopedRecordSupport.mergeRecords(local: recurringTaskTags, remote: remoteRecurringTaskTags),
            rewardTags: rewardTags
        )
    }

    func mergeRewardTags(_ remoteRewardTags: [RewardTag]) {
        guard !remoteRewardTags.isEmpty else { return }
        replaceAll(
            tags: tags,
            taskTags: taskTags,
            recurringTaskTags: recurringTaskTags,
            rewardTags: OwnerScopedRecordSupport.mergeRecords(local: rewardTags, remote: remoteRewardTags)
        )
    }

    func replaceAll(
        tags authoritativeTags: [Tag],
        taskTags authoritativeTaskTags: [TaskTag],
        recurringTaskTags authoritativeRecurringTaskTags: [RecurringTaskTag],
        rewardTags authoritativeRewardTags: [RewardTag]
    ) {
        let sortedTags = OwnerScopedRecordSupport.sorted(authoritativeTags)
        let sortedTaskTags = OwnerScopedRecordSupport.sorted(authoritativeTaskTags)
        let sortedRecurringTaskTags = OwnerScopedRecordSupport.sorted(authoritativeRecurringTaskTags)
        let sortedRewardTags = OwnerScopedRecordSupport.sorted(authoritativeRewardTags)

        do {
            try persistReplacedAll(tags: sortedTags, taskTags: sortedTaskTags, recurringTaskTags: sortedRecurringTaskTags, rewardTags: sortedRewardTags)
        } catch {
            assertionFailure("Failed to replace tag data: \(error)")
            return
        }
    }

    func getDirtyTags(ids: Set<RecordID>) -> [Tag] {
        tags.filter { ids.contains($0.id) }
    }

    func getDirtyTaskTags(ids: Set<RecordID>) -> [TaskTag] {
        taskTags.filter { ids.contains($0.id) }
    }

    func getDirtyRecurringTaskTags(ids: Set<RecordID>) -> [RecurringTaskTag] {
        recurringTaskTags.filter { ids.contains($0.id) }
    }

    func getDirtyRewardTags(ids: Set<RecordID>) -> [RewardTag] {
        rewardTags.filter { ids.contains($0.id) }
    }

    func purgeDeleted(
        excludingTagIDs dirtyTagIDs: Set<RecordID> = [],
        taskTagIDs dirtyTaskTagIDs: Set<RecordID> = [],
        recurringTaskTagIDs dirtyRecurringTaskTagIDs: Set<RecordID> = [],
        rewardTagIDs dirtyRewardTagIDs: Set<RecordID> = []
    ) {
        do {
            try persistDeletedPurge(
                excludingTagIDs: dirtyTagIDs,
                taskTagIDs: dirtyTaskTagIDs,
                recurringTaskTagIDs: dirtyRecurringTaskTagIDs,
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

    func allTaskTagIDs() -> [RecordID] {
        taskTags.map(\.id)
    }

    func allRecurringTaskTagIDs() -> [RecordID] {
        recurringTaskTags.map(\.id)
    }

    func allRewardTagIDs() -> [RecordID] {
        rewardTags.map(\.id)
    }

    func migrateData(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> (tagIDs: [RecordID], taskTagIDs: [RecordID], recurringTaskTagIDs: [RecordID], rewardTagIDs: [RecordID]) {
        guard sourceOwnerID != destinationOwnerID else {
            return ([], [], [], [])
        }

        let sourceTags = loadTags(ownerID: sourceOwnerID)
        let sourceTaskTags = loadTaskTags(ownerID: sourceOwnerID)
        let sourceRecurringTaskTags = loadRecurringTaskTags(ownerID: sourceOwnerID)
        let sourceRewardTags = loadRewardTags(ownerID: sourceOwnerID)

        let destinationTags = loadTags(ownerID: destinationOwnerID)
        let destinationTaskTags = loadTaskTags(ownerID: destinationOwnerID)
        let destinationRecurringTaskTags = loadRecurringTaskTags(ownerID: destinationOwnerID)
        let destinationRewardTags = loadRewardTags(ownerID: destinationOwnerID)

        let mergedTags = OwnerScopedRecordSupport.mergeRecords(local: destinationTags, remote: sourceTags)
        let mergedTaskTags = OwnerScopedRecordSupport.mergeRecords(local: destinationTaskTags, remote: sourceTaskTags)
        let mergedRecurringTaskTags = OwnerScopedRecordSupport.mergeRecords(local: destinationRecurringTaskTags, remote: sourceRecurringTaskTags)
        let mergedRewardTags = OwnerScopedRecordSupport.mergeRecords(local: destinationRewardTags, remote: sourceRewardTags)

        // Clear the local-owner rows first so sign-in migration can rebuild the
        // account-owned tag graph without colliding on globally unique tag ids.
        try replaceTagRows(ownerID: sourceOwnerID, tags: [], on: databaseHandle)
        try replaceTaskTagRows(ownerID: sourceOwnerID, rows: [], on: databaseHandle)
        try replaceRecurringTaskTagRows(ownerID: sourceOwnerID, rows: [], on: databaseHandle)
        try replaceRewardTagRows(ownerID: sourceOwnerID, rows: [], on: databaseHandle)

        try replaceTagRows(ownerID: destinationOwnerID, tags: mergedTags, on: databaseHandle)
        try replaceTaskTagRows(ownerID: destinationOwnerID, rows: mergedTaskTags, on: databaseHandle)
        try replaceRecurringTaskTagRows(ownerID: destinationOwnerID, rows: mergedRecurringTaskTags, on: databaseHandle)
        try replaceRewardTagRows(ownerID: destinationOwnerID, rows: mergedRewardTags, on: databaseHandle)

        return (
            sourceTags.map(\.id),
            sourceTaskTags.map(\.id),
            sourceRecurringTaskTags.map(\.id),
            sourceRewardTags.map(\.id)
        )
    }

    func persistReplacedAll(
        tags authoritativeTags: [Tag],
        taskTags authoritativeTaskTags: [TaskTag],
        recurringTaskTags authoritativeRecurringTaskTags: [RecurringTaskTag],
        rewardTags authoritativeRewardTags: [RewardTag]
    ) throws {
        let sortedTags = OwnerScopedRecordSupport.sorted(authoritativeTags)
        let sortedTaskTags = OwnerScopedRecordSupport.sorted(authoritativeTaskTags)
        let sortedRecurringTaskTags = OwnerScopedRecordSupport.sorted(authoritativeRecurringTaskTags)
        let sortedRewardTags = OwnerScopedRecordSupport.sorted(authoritativeRewardTags)

        try database.transaction(at: databaseURL) { db in
            try self.replaceTagRows(ownerID: self.currentOwnerID, tags: sortedTags, on: db)
            try self.replaceTaskTagRows(ownerID: self.currentOwnerID, rows: sortedTaskTags, on: db)
            try self.replaceRecurringTaskTagRows(ownerID: self.currentOwnerID, rows: sortedRecurringTaskTags, on: db)
            try self.replaceRewardTagRows(ownerID: self.currentOwnerID, rows: sortedRewardTags, on: db)
        }

        tags = sortedTags
        taskTags = sortedTaskTags
        recurringTaskTags = sortedRecurringTaskTags
        rewardTags = sortedRewardTags
    }

    func replaceAll(
        tags authoritativeTags: [Tag],
        taskTags authoritativeTaskTags: [TaskTag],
        recurringTaskTags authoritativeRecurringTaskTags: [RecurringTaskTag],
        rewardTags authoritativeRewardTags: [RewardTag],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try replaceTagRows(ownerID: currentOwnerID, tags: OwnerScopedRecordSupport.sorted(authoritativeTags), on: databaseHandle)
        try replaceTaskTagRows(ownerID: currentOwnerID, rows: OwnerScopedRecordSupport.sorted(authoritativeTaskTags), on: databaseHandle)
        try replaceRecurringTaskTagRows(ownerID: currentOwnerID, rows: OwnerScopedRecordSupport.sorted(authoritativeRecurringTaskTags), on: databaseHandle)
        try replaceRewardTagRows(ownerID: currentOwnerID, rows: OwnerScopedRecordSupport.sorted(authoritativeRewardTags), on: databaseHandle)
    }

    func persistDeletedPurge(
        excludingTagIDs dirtyTagIDs: Set<RecordID>,
        taskTagIDs dirtyTaskTagIDs: Set<RecordID>,
        recurringTaskTagIDs dirtyRecurringTaskTagIDs: Set<RecordID>,
        rewardTagIDs dirtyRewardTagIDs: Set<RecordID>
    ) throws {
        try database.transaction(at: databaseURL) { db in
            try self.purgeDeleted(
                excludingTagIDs: dirtyTagIDs,
                taskTagIDs: dirtyTaskTagIDs,
                recurringTaskTagIDs: dirtyRecurringTaskTagIDs,
                rewardTagIDs: dirtyRewardTagIDs,
                on: db
            )
        }
        refreshAll()
    }

    func purgeDeleted(
        excludingTagIDs dirtyTagIDs: Set<RecordID>,
        taskTagIDs dirtyTaskTagIDs: Set<RecordID>,
        recurringTaskTagIDs dirtyRecurringTaskTagIDs: Set<RecordID>,
        rewardTagIDs dirtyRewardTagIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try purgeDeletedTags(dirtyTagIDs, on: databaseHandle)
        try purgeDeletedTaskTags(dirtyTaskTagIDs, on: databaseHandle)
        try purgeDeletedRecurringTaskTags(dirtyRecurringTaskTagIDs, on: databaseHandle)
        try purgeDeletedRewardTags(dirtyRewardTagIDs, on: databaseHandle)
    }

    func deleteTagAssociations(
        taskTagIDs: Set<RecordID>,
        recurringTaskTagIDs: Set<RecordID>,
        rewardTagIDs: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try deleteAssociations(
            tableName: "task_tags",
            keyColumnA: "task_id",
            keyColumnB: "tag_id",
            ids: taskTagIDs,
            on: databaseHandle
        )
        try deleteAssociations(
            tableName: "recurring_task_tags",
            keyColumnA: "recurring_task_id",
            keyColumnB: "tag_id",
            ids: recurringTaskTagIDs,
            on: databaseHandle
        )
        try deleteAssociations(
            tableName: "reward_tags",
            keyColumnA: "reward_id",
            keyColumnB: "tag_id",
            ids: rewardTagIDs,
            on: databaseHandle
        )
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

    private func upsertRecurringTaskTag(_ row: RecurringTaskTag, markDirty: Bool) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.upsertRecurringTaskTag(row, on: db)
                if markDirty, self.currentOwnerID != StorageOwner.local {
                    try self.syncStateStore.markDirty(userID: self.currentOwnerID, kind: .recurringTaskTags, ids: [row.id], on: db)
                }
            }
        } catch {
            assertionFailure("Failed to upsert recurringTask tag: \(error)")
            return
        }
        refreshAll()
    }

    private func upsertTaskTag(_ row: TaskTag, markDirty: Bool) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.upsertTaskTag(row, on: db)
                if markDirty, self.currentOwnerID != StorageOwner.local {
                    try self.syncStateStore.markDirty(userID: self.currentOwnerID, kind: .taskTags, ids: [row.id], on: db)
                }
            }
        } catch {
            assertionFailure("Failed to upsert task tag: \(error)")
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
            INSERT INTO tags (id, owner_id, name, color_hex, created_at, updated_at, deleted_at, server_revision)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                owner_id = excluded.owner_id,
                name = excluded.name,
                color_hex = excluded.color_hex,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                server_revision = excluded.server_revision
            """,
            bindings: tagBindings(tag, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func upsertRecurringTaskTag(_ row: RecurringTaskTag, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO recurring_task_tags (owner_id, recurring_task_id, tag_id, created_at, updated_at, deleted_at, server_revision)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_id, recurring_task_id, tag_id) DO UPDATE SET
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                server_revision = excluded.server_revision
            """,
            bindings: recurringTaskTagBindings(row, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func upsertTaskTag(_ row: TaskTag, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO task_tags (owner_id, task_id, tag_id, created_at, updated_at, deleted_at, server_revision)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_id, task_id, tag_id) DO UPDATE SET
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                server_revision = excluded.server_revision
            """,
            bindings: taskTagBindings(row, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func upsertRewardTag(_ row: RewardTag, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO reward_tags (owner_id, reward_id, tag_id, created_at, updated_at, deleted_at, server_revision)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_id, reward_id, tag_id) DO UPDATE SET
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                server_revision = excluded.server_revision
            """,
            bindings: rewardTagBindings(row, ownerID: currentOwnerID),
            on: databaseHandle
        )
    }

    private func loadTags(ownerID: String) -> [Tag] {
        let fetched = (try? database.query(
            """
            SELECT id, name, color_hex, created_at, updated_at, deleted_at, server_revision
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
                deletedAt: SQLiteColumn.optionalDate(row, index: 5),
                serverRevision: SQLiteColumn.optionalInt64(row, index: 6)
            )
        }) ?? []
        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func loadRecurringTaskTags(ownerID: String) -> [RecurringTaskTag] {
        let fetched = (try? database.query(
            """
            SELECT recurring_task_id, tag_id, created_at, updated_at, deleted_at, server_revision
            FROM recurring_task_tags
            WHERE owner_id = ?
            ORDER BY created_at ASC, recurring_task_id ASC, tag_id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            RecurringTaskTag(
                recurringTaskId: RecordID(SQLiteColumn.text(row, index: 0)),
                tagId: RecordID(SQLiteColumn.text(row, index: 1)),
                createdAt: SQLiteColumn.date(row, index: 2),
                updatedAt: SQLiteColumn.date(row, index: 3),
                deletedAt: SQLiteColumn.optionalDate(row, index: 4),
                serverRevision: SQLiteColumn.optionalInt64(row, index: 5)
            )
        }) ?? []
        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func loadTaskTags(ownerID: String) -> [TaskTag] {
        let fetched = (try? database.query(
            """
            SELECT task_id, tag_id, created_at, updated_at, deleted_at, server_revision
            FROM task_tags
            WHERE owner_id = ?
            ORDER BY created_at ASC, task_id ASC, tag_id ASC
            """,
            bindings: [.text(ownerID)],
            at: databaseURL
        ) { row in
            TaskTag(
                taskId: RecordID(SQLiteColumn.text(row, index: 0)),
                tagId: RecordID(SQLiteColumn.text(row, index: 1)),
                createdAt: SQLiteColumn.date(row, index: 2),
                updatedAt: SQLiteColumn.date(row, index: 3),
                deletedAt: SQLiteColumn.optionalDate(row, index: 4),
                serverRevision: SQLiteColumn.optionalInt64(row, index: 5)
            )
        }) ?? []
        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func loadRewardTags(ownerID: String) -> [RewardTag] {
        let fetched = (try? database.query(
            """
            SELECT reward_id, tag_id, created_at, updated_at, deleted_at, server_revision
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
                deletedAt: SQLiteColumn.optionalDate(row, index: 4),
                serverRevision: SQLiteColumn.optionalInt64(row, index: 5)
            )
        }) ?? []
        return OwnerScopedRecordSupport.sorted(fetched)
    }

    private func refreshAll() {
        tags = loadTags(ownerID: currentOwnerID)
        taskTags = loadTaskTags(ownerID: currentOwnerID)
        recurringTaskTags = loadRecurringTaskTags(ownerID: currentOwnerID)
        rewardTags = loadRewardTags(ownerID: currentOwnerID)
    }

    private func replaceTagRows(ownerID: String, tags: [Tag], on databaseHandle: AppDatabaseHandle) throws {
        try database.execute("DELETE FROM tags WHERE owner_id = ?", bindings: [.text(ownerID)], on: databaseHandle)
        for tag in tags {
            try database.execute(
                """
                INSERT INTO tags (id, owner_id, name, color_hex, created_at, updated_at, deleted_at, server_revision)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: tagBindings(tag, ownerID: ownerID),
                on: databaseHandle
            )
        }
    }

    private func replaceTaskTagRows(ownerID: String, rows: [TaskTag], on databaseHandle: AppDatabaseHandle) throws {
        try database.execute("DELETE FROM task_tags WHERE owner_id = ?", bindings: [.text(ownerID)], on: databaseHandle)
        for row in rows {
            try database.execute(
                """
                INSERT INTO task_tags (owner_id, task_id, tag_id, created_at, updated_at, deleted_at, server_revision)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: taskTagBindings(row, ownerID: ownerID),
                on: databaseHandle
            )
        }
    }

    private func replaceRecurringTaskTagRows(ownerID: String, rows: [RecurringTaskTag], on databaseHandle: AppDatabaseHandle) throws {
        try database.execute("DELETE FROM recurring_task_tags WHERE owner_id = ?", bindings: [.text(ownerID)], on: databaseHandle)
        for row in rows {
            try database.execute(
                """
                INSERT INTO recurring_task_tags (owner_id, recurring_task_id, tag_id, created_at, updated_at, deleted_at, server_revision)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: recurringTaskTagBindings(row, ownerID: ownerID),
                on: databaseHandle
            )
        }
    }

    private func replaceRewardTagRows(ownerID: String, rows: [RewardTag], on databaseHandle: AppDatabaseHandle) throws {
        try database.execute("DELETE FROM reward_tags WHERE owner_id = ?", bindings: [.text(ownerID)], on: databaseHandle)
        for row in rows {
            try database.execute(
                """
                INSERT INTO reward_tags (owner_id, reward_id, tag_id, created_at, updated_at, deleted_at, server_revision)
                VALUES (?, ?, ?, ?, ?, ?, ?)
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
        let bindings: [SQLiteValue] = [SQLiteValue.text(currentOwnerID)]
            + dirtyTagIDs.sorted { $0.rawValue < $1.rawValue }.map { SQLiteValue.text($0.rawValue) }
        try database.execute(
            "DELETE FROM tags WHERE owner_id = ? AND deleted_at IS NOT NULL AND id NOT IN (\(placeholders))",
            bindings: bindings,
            on: databaseHandle
        )
    }

    private func purgeDeletedRecurringTaskTags(_ dirtyRecurringTaskTagIDs: Set<RecordID>, on databaseHandle: AppDatabaseHandle) throws {
        try purgeDeletedAssociations(
            tableName: "recurring_task_tags",
            keyColumnA: "recurring_task_id",
            keyColumnB: "tag_id",
            dirtyIDs: dirtyRecurringTaskTagIDs,
            on: databaseHandle
        )
    }

    private func purgeDeletedTaskTags(_ dirtyTaskTagIDs: Set<RecordID>, on databaseHandle: AppDatabaseHandle) throws {
        try purgeDeletedAssociations(
            tableName: "task_tags",
            keyColumnA: "task_id",
            keyColumnB: "tag_id",
            dirtyIDs: dirtyTaskTagIDs,
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

    private func deleteAssociations(
        tableName: String,
        keyColumnA: String,
        keyColumnB: String,
        ids: Set<RecordID>,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        for id in ids {
            let parts = id.rawValue.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }

            try database.execute(
                "DELETE FROM \(tableName) WHERE owner_id = ? AND \(keyColumnA) = ? AND \(keyColumnB) = ?",
                bindings: [.text(currentOwnerID), .text(parts[0]), .text(parts[1])],
                on: databaseHandle
            )
        }
    }

    private func tagBindings(_ tag: Tag, ownerID: String) -> [SQLiteValue] {
        [
            .text(tag.id.rawValue),
            .text(ownerID),
            .text(tag.name),
            .text(tag.colorHex),
            .double(tag.createdAt.timeIntervalSince1970),
            .double(tag.updatedAt.timeIntervalSince1970),
            tag.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            tag.serverRevision.map { .int($0) } ?? .null
        ]
    }

    private func recurringTaskTagBindings(_ row: RecurringTaskTag, ownerID: String) -> [SQLiteValue] {
        [
            .text(ownerID),
            .text(row.recurringTaskId.rawValue),
            .text(row.tagId.rawValue),
            .double(row.createdAt.timeIntervalSince1970),
            .double(row.updatedAt.timeIntervalSince1970),
            row.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            row.serverRevision.map { .int($0) } ?? .null
        ]
    }

    private func taskTagBindings(_ row: TaskTag, ownerID: String) -> [SQLiteValue] {
        [
            .text(ownerID),
            .text(row.taskId.rawValue),
            .text(row.tagId.rawValue),
            .double(row.createdAt.timeIntervalSince1970),
            .double(row.updatedAt.timeIntervalSince1970),
            row.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            row.serverRevision.map { .int($0) } ?? .null
        ]
    }

    private func rewardTagBindings(_ row: RewardTag, ownerID: String) -> [SQLiteValue] {
        [
            .text(ownerID),
            .text(row.rewardId.rawValue),
            .text(row.tagId.rawValue),
            .double(row.createdAt.timeIntervalSince1970),
            .double(row.updatedAt.timeIntervalSince1970),
            row.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            row.serverRevision.map { .int($0) } ?? .null
        ]
    }

    private func notifySync(kind: SyncEntityKind, ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: kind, recordIDs: ids))
    }
}
