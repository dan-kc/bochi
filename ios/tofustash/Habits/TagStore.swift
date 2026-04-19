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
        self.tags = self.tagsByOwner[initialOwnerID] ?? []
        self.habitTags = self.habitTagsByOwner[initialOwnerID] ?? []
        self.rewardTags = self.rewardTagsByOwner[initialOwnerID] ?? []
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        tags = tagsByOwner[ownerID] ?? []
        habitTags = habitTagsByOwner[ownerID] ?? []
        rewardTags = rewardTagsByOwner[ownerID] ?? []
    }

    func migrateData(from sourceOwnerID: String, to destinationOwnerID: String) -> (tagIDs: [RecordID], habitTagIDs: [RecordID], rewardTagIDs: [RecordID]) {
        guard sourceOwnerID != destinationOwnerID else {
            return ([], [], [])
        }

        let sourceTags = tagsByOwner[sourceOwnerID] ?? []
        let sourceHabitTags = habitTagsByOwner[sourceOwnerID] ?? []
        let sourceRewardTags = rewardTagsByOwner[sourceOwnerID] ?? []

        tagsByOwner[destinationOwnerID] = mergeTags(local: tagsByOwner[destinationOwnerID] ?? [], remote: sourceTags)
        habitTagsByOwner[destinationOwnerID] = mergeHabitTags(local: habitTagsByOwner[destinationOwnerID] ?? [], remote: sourceHabitTags)
        rewardTagsByOwner[destinationOwnerID] = mergeRewardTags(local: rewardTagsByOwner[destinationOwnerID] ?? [], remote: sourceRewardTags)

        tagsByOwner[sourceOwnerID] = []
        habitTagsByOwner[sourceOwnerID] = []
        rewardTagsByOwner[sourceOwnerID] = []

        persist()
        setCurrentOwner(currentOwnerID)

        return (
            sourceTags.map(\.id),
            sourceHabitTags.map(\.id),
            sourceRewardTags.map(\.id)
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

    func listFilterTags(for scope: EntityListTagScope) -> [Tag] {
        let validTagIDs = listFilterTagIDs(for: scope)
        return activeTags.filter { validTagIDs.contains($0.id) }
    }

    func listFilterTagIDs(for scope: EntityListTagScope) -> Set<RecordID> {
        let activeTagIDs = Set(activeTags.map(\.id))

        let usedTagIDs: Set<RecordID>
        switch scope {
        case .habits:
            usedTagIDs = Set(
                habitTags
                    .filter { $0.deletedAt == nil }
                    .map(\.tagId)
            )
        case .rewards:
            usedTagIDs = Set(
                rewardTags
                    .filter { $0.deletedAt == nil }
                    .map(\.tagId)
            )
        }

        return activeTagIDs.intersection(usedTagIDs)
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
            $0 = mergeTags(local: $0, remote: remoteTags)
        }
    }

    func mergeHabitTags(_ remoteHabitTags: [HabitTag]) {
        guard !remoteHabitTags.isEmpty else { return }
        mutateHabitTags {
            $0 = mergeHabitTags(local: $0, remote: remoteHabitTags)
        }
    }

    func mergeRewardTags(_ remoteRewardTags: [RewardTag]) {
        guard !remoteRewardTags.isEmpty else { return }
        mutateRewardTags {
            $0 = mergeRewardTags(local: $0, remote: remoteRewardTags)
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
        var next = tags
        mutate(&next)
        next.sort { $0.createdAt < $1.createdAt }
        tags = next
        tagsByOwner[currentOwnerID] = next
        persist()
    }

    private func mutateHabitTags(_ mutate: (inout [HabitTag]) -> Void) {
        var next = habitTags
        mutate(&next)
        next.sort { $0.createdAt < $1.createdAt }
        habitTags = next
        habitTagsByOwner[currentOwnerID] = next
        persist()
    }

    private func mutateRewardTags(_ mutate: (inout [RewardTag]) -> Void) {
        var next = rewardTags
        mutate(&next)
        next.sort { $0.createdAt < $1.createdAt }
        rewardTags = next
        rewardTagsByOwner[currentOwnerID] = next
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

    private func mergeTags(local: [Tag], remote: [Tag]) -> [Tag] {
        var mergedByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

        for incoming in remote {
            if let existing = mergedByID[incoming.id], existing.updatedAt > incoming.updatedAt {
                continue
            }
            mergedByID[incoming.id] = incoming
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.rawValue < rhs.id.rawValue
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func mergeHabitTags(local: [HabitTag], remote: [HabitTag]) -> [HabitTag] {
        var mergedByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

        for incoming in remote {
            if let existing = mergedByID[incoming.id], existing.updatedAt > incoming.updatedAt {
                continue
            }
            mergedByID[incoming.id] = incoming
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.rawValue < rhs.id.rawValue
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func mergeRewardTags(local: [RewardTag], remote: [RewardTag]) -> [RewardTag] {
        var mergedByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

        for incoming in remote {
            if let existing = mergedByID[incoming.id], existing.updatedAt > incoming.updatedAt {
                continue
            }
            mergedByID[incoming.id] = incoming
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.rawValue < rhs.id.rawValue
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func notifySync(kind: SyncEntityKind, ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: kind, recordIDs: ids))
    }

    private static func normalizePersistedTags(_ tagsByOwner: [String: [Tag]]) -> [String: [Tag]] {
        Dictionary(uniqueKeysWithValues: tagsByOwner.map { ownerID, tags in
            (ownerID, normalizeTags(tags))
        })
    }

    private static func normalizePersistedHabitTags(_ habitTagsByOwner: [String: [HabitTag]]) -> [String: [HabitTag]] {
        Dictionary(uniqueKeysWithValues: habitTagsByOwner.map { ownerID, habitTags in
            (ownerID, normalizeHabitTags(habitTags))
        })
    }

    private static func normalizePersistedRewardTags(_ rewardTagsByOwner: [String: [RewardTag]]) -> [String: [RewardTag]] {
        Dictionary(uniqueKeysWithValues: rewardTagsByOwner.map { ownerID, rewardTags in
            (ownerID, normalizeRewardTags(rewardTags))
        })
    }

    private static func normalizeTags(_ tags: [Tag]) -> [Tag] {
        var newestByID: [RecordID: Tag] = [:]

        for tag in tags {
            let normalized = Tag(
                id: RecordID(rawValue: tag.id.rawValue),
                name: tag.name,
                colorHex: tag.colorHex,
                createdAt: tag.createdAt,
                updatedAt: tag.updatedAt,
                deletedAt: tag.deletedAt
            )

            if let existing = newestByID[normalized.id], existing.updatedAt > normalized.updatedAt {
                continue
            }

            newestByID[normalized.id] = normalized
        }

        return newestByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.rawValue < rhs.id.rawValue
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private static func normalizeHabitTags(_ habitTags: [HabitTag]) -> [HabitTag] {
        var newestByID: [RecordID: HabitTag] = [:]

        for habitTag in habitTags {
            let normalized = HabitTag(
                habitId: RecordID(rawValue: habitTag.habitId.rawValue),
                tagId: RecordID(rawValue: habitTag.tagId.rawValue),
                createdAt: habitTag.createdAt,
                updatedAt: habitTag.updatedAt,
                deletedAt: habitTag.deletedAt
            )

            if let existing = newestByID[normalized.id], existing.updatedAt > normalized.updatedAt {
                continue
            }

            newestByID[normalized.id] = normalized
        }

        return newestByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.rawValue < rhs.id.rawValue
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private static func normalizeRewardTags(_ rewardTags: [RewardTag]) -> [RewardTag] {
        var newestByID: [RecordID: RewardTag] = [:]

        for rewardTag in rewardTags {
            let normalized = RewardTag(
                rewardId: RecordID(rawValue: rewardTag.rewardId.rawValue),
                tagId: RecordID(rawValue: rewardTag.tagId.rawValue),
                createdAt: rewardTag.createdAt,
                updatedAt: rewardTag.updatedAt,
                deletedAt: rewardTag.deletedAt
            )

            if let existing = newestByID[normalized.id], existing.updatedAt > normalized.updatedAt {
                continue
            }

            newestByID[normalized.id] = normalized
        }

        return newestByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.rawValue < rhs.id.rawValue
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
