import Foundation

enum EntityListTagScope {
    case habits
    case rewards
}

@Observable
@MainActor
final class TagStore {
    private struct PersistedState: Codable {
        var tagsByOwner: [String: [Tag]] = [:]
        var habitTagsByOwner: [String: [HabitTag]] = [:]
        var rewardTagsByOwner: [String: [RewardTag]] = [:]
    }

    private let storageURL: URL
    private(set) var currentOwnerID: String
    private var tagsByOwner: [String: [Tag]]
    private var habitTagsByOwner: [String: [HabitTag]]
    private var rewardTagsByOwner: [String: [RewardTag]]

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
        self.storageURL = storageURL ?? AppStorageLocation.fileURL(filename: "tags")
        self.currentOwnerID = initialOwnerID
        let persisted = JSONFileStore.load(PersistedState.self, from: self.storageURL, defaultValue: PersistedState())
        self.tagsByOwner = Self.normalizePersistedTags(persisted.tagsByOwner)
        self.habitTagsByOwner = Self.normalizePersistedHabitTags(persisted.habitTagsByOwner)
        self.rewardTagsByOwner = Self.normalizePersistedRewardTags(persisted.rewardTagsByOwner)
        self.tags = OwnerScopedRecordSupport.recordsForOwner(self.tagsByOwner, ownerID: initialOwnerID)
        self.habitTags = OwnerScopedRecordSupport.recordsForOwner(self.habitTagsByOwner, ownerID: initialOwnerID)
        self.rewardTags = OwnerScopedRecordSupport.recordsForOwner(self.rewardTagsByOwner, ownerID: initialOwnerID)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        tags = OwnerScopedRecordSupport.recordsForOwner(tagsByOwner, ownerID: ownerID)
        habitTags = OwnerScopedRecordSupport.recordsForOwner(habitTagsByOwner, ownerID: ownerID)
        rewardTags = OwnerScopedRecordSupport.recordsForOwner(rewardTagsByOwner, ownerID: ownerID)
    }

    func migrateData(from sourceOwnerID: String, to destinationOwnerID: String) -> (tagIDs: [RecordID], habitTagIDs: [RecordID], rewardTagIDs: [RecordID]) {
        guard sourceOwnerID != destinationOwnerID else {
            return ([], [], [])
        }

        let migratedTagIDs = OwnerScopedRecordSupport.migrateRecords(
            from: sourceOwnerID,
            to: destinationOwnerID,
            recordsByOwner: &tagsByOwner
        )
        let migratedHabitTagIDs = OwnerScopedRecordSupport.migrateRecords(
            from: sourceOwnerID,
            to: destinationOwnerID,
            recordsByOwner: &habitTagsByOwner
        )
        let migratedRewardTagIDs = OwnerScopedRecordSupport.migrateRecords(
            from: sourceOwnerID,
            to: destinationOwnerID,
            recordsByOwner: &rewardTagsByOwner
        )

        persist()
        setCurrentOwner(currentOwnerID)

        return (
            migratedTagIDs,
            migratedHabitTagIDs,
            migratedRewardTagIDs
        )
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

        mutateTags {
            $0.removeAll { $0.id == tag.id }
            $0.append(tag)
        }

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
        let canonicalID = id
        guard let index = tags.firstIndex(where: { $0.id == canonicalID }) else { return }

        let existing = tags[index]
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

        mutateTags { $0[index] = updated }

        if shouldNotifySync {
            notifySync(kind: .tags, ids: [canonicalID])
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

        mutateHabitTags {
            if let index = $0.firstIndex(where: { $0.id == association.id }) {
                $0[index] = association
            } else {
                $0.append(association)
            }
        }

        if shouldNotifySync {
            notifySync(kind: .habitTags, ids: [association.id])
        }
    }

    func removeTagFromHabit(tagId: RecordID, habitId: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        let canonicalTagID = tagId
        let canonicalHabitID = habitId
        guard let index = habitTags.firstIndex(where: {
            $0.tagId == canonicalTagID && $0.habitId == canonicalHabitID && $0.deletedAt == nil
        }) else { return }

        let existing = habitTags[index]
        let deleted = HabitTag(
            habitId: existing.habitId,
            tagId: existing.tagId,
            createdAt: existing.createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt
        )

        mutateHabitTags { $0[index] = deleted }

        if shouldNotifySync {
            notifySync(kind: .habitTags, ids: [deleted.id])
        }
    }

    func tagsForHabit(habitId: RecordID) -> [Tag] {
        let canonicalHabitID = habitId
        let activeTagIDs = Set(
            habitTags
                .filter { $0.habitId == canonicalHabitID && $0.deletedAt == nil }
                .map(\.tagId)
        )

        return activeTags.filter { activeTagIDs.contains($0.id) }
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

        mutateRewardTags {
            if let index = $0.firstIndex(where: { $0.id == association.id }) {
                $0[index] = association
            } else {
                $0.append(association)
            }
        }

        if shouldNotifySync {
            notifySync(kind: .rewardTags, ids: [association.id])
        }
    }

    func removeTagFromReward(tagId: RecordID, rewardId: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        let canonicalTagID = tagId
        let canonicalRewardID = rewardId
        guard let index = rewardTags.firstIndex(where: {
            $0.tagId == canonicalTagID && $0.rewardId == canonicalRewardID && $0.deletedAt == nil
        }) else { return }

        let existing = rewardTags[index]
        let deleted = RewardTag(
            rewardId: existing.rewardId,
            tagId: existing.tagId,
            createdAt: existing.createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt
        )

        mutateRewardTags { $0[index] = deleted }

        if shouldNotifySync {
            notifySync(kind: .rewardTags, ids: [deleted.id])
        }
    }

    func tagsForReward(rewardId: RecordID) -> [Tag] {
        let canonicalRewardID = rewardId
        let activeTagIDs = Set(
            rewardTags
                .filter { $0.rewardId == canonicalRewardID && $0.deletedAt == nil }
                .map(\.tagId)
        )

        return activeTags.filter { activeTagIDs.contains($0.id) }
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
        mutateTags {
            $0 = OwnerScopedRecordSupport.mergeRecords(local: $0, remote: remoteTags)
        }
    }

    func mergeHabitTags(_ remoteHabitTags: [HabitTag]) {
        guard !remoteHabitTags.isEmpty else { return }
        mutateHabitTags {
            $0 = OwnerScopedRecordSupport.mergeRecords(local: $0, remote: remoteHabitTags)
        }
    }

    func mergeRewardTags(_ remoteRewardTags: [RewardTag]) {
        guard !remoteRewardTags.isEmpty else { return }
        mutateRewardTags {
            $0 = OwnerScopedRecordSupport.mergeRecords(local: $0, remote: remoteRewardTags)
        }
    }

    func replaceAll(
        tags authoritativeTags: [Tag],
        habitTags authoritativeHabitTags: [HabitTag],
        rewardTags authoritativeRewardTags: [RewardTag]
    ) {
        tags = OwnerScopedRecordSupport.sorted(authoritativeTags)
        habitTags = OwnerScopedRecordSupport.sorted(authoritativeHabitTags)
        rewardTags = OwnerScopedRecordSupport.sorted(authoritativeRewardTags)
        tagsByOwner[currentOwnerID] = tags
        habitTagsByOwner[currentOwnerID] = habitTags
        rewardTagsByOwner[currentOwnerID] = rewardTags
        persist()
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

    func purgeDeleted() {
        mutateTags { $0.removeAll { $0.deletedAt != nil } }
        mutateHabitTags { $0.removeAll { $0.deletedAt != nil } }
        mutateRewardTags { $0.removeAll { $0.deletedAt != nil } }
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

    private func mutateTags(_ mutate: (inout [Tag]) -> Void) {
        tags = OwnerScopedRecordSupport.mutateRecords(
            currentRecords: tags,
            ownerID: currentOwnerID,
            recordsByOwner: &tagsByOwner,
            mutate: mutate
        )
        persist()
    }

    private func mutateHabitTags(_ mutate: (inout [HabitTag]) -> Void) {
        habitTags = OwnerScopedRecordSupport.mutateRecords(
            currentRecords: habitTags,
            ownerID: currentOwnerID,
            recordsByOwner: &habitTagsByOwner,
            mutate: mutate
        )
        persist()
    }

    private func mutateRewardTags(_ mutate: (inout [RewardTag]) -> Void) {
        rewardTags = OwnerScopedRecordSupport.mutateRecords(
            currentRecords: rewardTags,
            ownerID: currentOwnerID,
            recordsByOwner: &rewardTagsByOwner,
            mutate: mutate
        )
        persist()
    }

    private func persist() {
        JSONFileStore.save(
            PersistedState(
                tagsByOwner: tagsByOwner,
                habitTagsByOwner: habitTagsByOwner,
                rewardTagsByOwner: rewardTagsByOwner
            ),
            to: storageURL
        )
    }

    private func notifySync(kind: SyncEntityKind, ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: kind, recordIDs: ids))
    }

    private static func normalizePersistedTags(_ tagsByOwner: [String: [Tag]]) -> [String: [Tag]] {
        OwnerScopedRecordSupport.normalizePersistedRecords(tagsByOwner) { tag in
            Tag(
                id: RecordID(rawValue: tag.id.rawValue),
                name: tag.name,
                colorHex: tag.colorHex,
                createdAt: tag.createdAt,
                updatedAt: tag.updatedAt,
                deletedAt: tag.deletedAt
            )
        }
    }

    private static func normalizePersistedHabitTags(_ habitTagsByOwner: [String: [HabitTag]]) -> [String: [HabitTag]] {
        OwnerScopedRecordSupport.normalizePersistedRecords(habitTagsByOwner) { habitTag in
            HabitTag(
                habitId: RecordID(rawValue: habitTag.habitId.rawValue),
                tagId: RecordID(rawValue: habitTag.tagId.rawValue),
                createdAt: habitTag.createdAt,
                updatedAt: habitTag.updatedAt,
                deletedAt: habitTag.deletedAt
            )
        }
    }

    private static func normalizePersistedRewardTags(_ rewardTagsByOwner: [String: [RewardTag]]) -> [String: [RewardTag]] {
        OwnerScopedRecordSupport.normalizePersistedRecords(rewardTagsByOwner) { rewardTag in
            RewardTag(
                rewardId: RecordID(rawValue: rewardTag.rewardId.rawValue),
                tagId: RecordID(rawValue: rewardTag.tagId.rawValue),
                createdAt: rewardTag.createdAt,
                updatedAt: rewardTag.updatedAt,
                deletedAt: rewardTag.deletedAt
            )
        }
    }
}
