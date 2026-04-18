import Foundation

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
        self.tagsByOwner = persisted.tagsByOwner
        self.habitTagsByOwner = persisted.habitTagsByOwner
        self.rewardTagsByOwner = persisted.rewardTagsByOwner
        self.tags = persisted.tagsByOwner[initialOwnerID] ?? []
        self.habitTags = persisted.habitTagsByOwner[initialOwnerID] ?? []
        self.rewardTags = persisted.rewardTagsByOwner[initialOwnerID] ?? []
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        tags = tagsByOwner[ownerID] ?? []
        habitTags = habitTagsByOwner[ownerID] ?? []
        rewardTags = rewardTagsByOwner[ownerID] ?? []
    }

    func migrateData(from sourceOwnerID: String, to destinationOwnerID: String) -> (tagIDs: [String], habitTagIDs: [String], rewardTagIDs: [String]) {
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
        id: String? = nil,
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
            id: id ?? UUID().uuidString,
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
        id: String,
        name: String? = nil,
        colorHex: String? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date?? = nil,
        shouldNotifySync: Bool = true
    ) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }

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
            notifySync(kind: .tags, ids: [id])
        }
    }

    func deleteTag(id: String, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        updateTag(id: id, updatedAt: deletedAt, deletedAt: .some(deletedAt), shouldNotifySync: shouldNotifySync)
    }

    func addTagToHabit(
        tagId: String,
        habitId: String,
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

    func removeTagFromHabit(tagId: String, habitId: String, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        guard let index = habitTags.firstIndex(where: {
            $0.tagId == tagId && $0.habitId == habitId && $0.deletedAt == nil
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

    func tagsForHabit(habitId: String) -> [Tag] {
        let activeTagIDs = Set(
            habitTags
                .filter { $0.habitId == habitId && $0.deletedAt == nil }
                .map(\.tagId)
        )

        return activeTags.filter { activeTagIDs.contains($0.id) }
    }

    func addTagToReward(
        tagId: String,
        rewardId: String,
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

    func removeTagFromReward(tagId: String, rewardId: String, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        guard let index = rewardTags.firstIndex(where: {
            $0.tagId == tagId && $0.rewardId == rewardId && $0.deletedAt == nil
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

    func tagsForReward(rewardId: String) -> [Tag] {
        let activeTagIDs = Set(
            rewardTags
                .filter { $0.rewardId == rewardId && $0.deletedAt == nil }
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

    func addTag(tagId: String, to target: TagAssignmentTarget) {
        switch target {
        case .habit(let habitId):
            addTagToHabit(tagId: tagId, habitId: habitId)
        case .reward(let rewardId):
            addTagToReward(tagId: tagId, rewardId: rewardId)
        }
    }

    func removeTag(tagId: String, from target: TagAssignmentTarget) {
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

    func getDirtyTags(ids: Set<String>) -> [Tag] {
        tags.filter { ids.contains($0.id) }
    }

    func getDirtyHabitTags(ids: Set<String>) -> [HabitTag] {
        habitTags.filter { ids.contains($0.id) }
    }

    func getDirtyRewardTags(ids: Set<String>) -> [RewardTag] {
        rewardTags.filter { ids.contains($0.id) }
    }

    func purgeDeleted() {
        mutateTags { $0.removeAll { $0.deletedAt != nil } }
        mutateHabitTags { $0.removeAll { $0.deletedAt != nil } }
        mutateRewardTags { $0.removeAll { $0.deletedAt != nil } }
    }

    func allTagIDs() -> [String] {
        tags.map(\.id)
    }

    func allHabitTagIDs() -> [String] {
        habitTags.map(\.id)
    }

    func allRewardTagIDs() -> [String] {
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
                return lhs.id < rhs.id
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
                return lhs.id < rhs.id
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
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func notifySync(kind: SyncEntityKind, ids: [String]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: kind, recordIDs: ids))
    }
}
