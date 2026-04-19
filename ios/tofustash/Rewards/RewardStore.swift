import Foundation

@Observable
@MainActor
final class RewardStore {
    private struct PersistedState: Codable {
        var rewardsByOwner: [String: [Reward]] = [:]
    }

    private let storageURL: URL
    private(set) var currentOwnerID: String
    private var rewardsByOwner: [String: [Reward]]

    private(set) var rewards: [Reward] = []

    var activeRewards: [Reward] {
        rewards.filter { $0.deletedAt == nil }
    }

    var rewardsSortedByDamage: [Reward] {
        activeRewards.sorted { lhs, rhs in
            switch (lhs.damageTier, rhs.damageTier) {
            case let (l?, r?):
                return l.sortOrder > r.sortOrder
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.createdAt < rhs.createdAt
            }
        }
    }

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.storageURL = storageURL ?? AppStorageLocation.fileURL(filename: "rewards")
        self.currentOwnerID = initialOwnerID
        let persisted = JSONFileStore.load(PersistedState.self, from: self.storageURL, defaultValue: PersistedState())
        self.rewardsByOwner = Self.normalizePersistedRewards(persisted.rewardsByOwner)
        self.rewards = self.rewardsByOwner[initialOwnerID] ?? []
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        rewards = rewardsByOwner[ownerID] ?? []
    }

    func migrateRewards(from sourceOwnerID: String, to destinationOwnerID: String) -> [String] {
        guard sourceOwnerID != destinationOwnerID else { return [] }

        let source = rewardsByOwner[sourceOwnerID] ?? []
        let destination = rewardsByOwner[destinationOwnerID] ?? []
        let merged = mergeRecords(local: destination, remote: source)
        let migratedIDs = source.map(\.id)

        rewardsByOwner[destinationOwnerID] = merged
        rewardsByOwner[sourceOwnerID] = []
        persist()
        refreshCurrentRewards()
        return migratedIDs
    }

    @discardableResult
    func addReward(
        id: String? = nil,
        name: String,
        description: String = "",
        maxFrequency: Double? = nil,
        damageTier: RewardDamageTier? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        shouldNotifySync: Bool = true
    ) -> Reward? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else {
            return nil
        }
        let canonicalID = CanonicalRecordID.normalize(id ?? UUID().uuidString)

        let now = Date()
        let reward = Reward(
            id: canonicalID,
            name: trimmedName,
            description: description,
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? now,
            deletedAt: deletedAt,
            maxFrequency: maxFrequency,
            damageTier: damageTier
        )

        mutateRewards {
            $0.removeAll { $0.id == reward.id }
            $0.append(reward)
        }

        if shouldNotifySync {
            notifySync(ids: [reward.id])
        }

        return reward
    }

    func updateReward(
        id: String,
        name: String? = nil,
        description: String? = nil,
        maxFrequency: Double?? = nil,
        damageTier: RewardDamageTier?? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date?? = nil,
        shouldNotifySync: Bool = true
    ) {
        let canonicalID = CanonicalRecordID.normalize(id)
        guard let index = rewards.firstIndex(where: { $0.id == canonicalID }) else {
            return
        }

        let existing = rewards[index]

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
            name: newName,
            description: description ?? existing.description,
            createdAt: existing.createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt ?? existing.deletedAt,
            maxFrequency: maxFrequency ?? existing.maxFrequency,
            damageTier: damageTier ?? existing.damageTier
        )

        mutateRewards { $0[index] = updated }

        if shouldNotifySync {
            notifySync(ids: [canonicalID])
        }
    }

    func deleteReward(id: String, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        let canonicalID = CanonicalRecordID.normalize(id)
        guard let index = rewards.firstIndex(where: { $0.id == canonicalID }) else {
            return
        }

        let existing = rewards[index]
        let deleted = Reward(
            id: existing.id,
            name: existing.name,
            description: existing.description,
            createdAt: existing.createdAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt,
            maxFrequency: existing.maxFrequency,
            damageTier: existing.damageTier
        )

        mutateRewards { $0[index] = deleted }

        if shouldNotifySync {
            notifySync(ids: [canonicalID])
        }
    }

    func mergeRewards(_ remoteRewards: [Reward]) {
        guard !remoteRewards.isEmpty else { return }
        mutateRewards {
            $0 = mergeRecords(local: $0, remote: remoteRewards)
        }
    }

    func getDirtyRewards(ids: Set<String>) -> [Reward] {
        rewards.filter { ids.contains($0.id) }
    }

    func purgeDeletedRewards() {
        mutateRewards {
            $0.removeAll { $0.deletedAt != nil }
        }
    }

    func allRewardIDs() -> [String] {
        rewards.map(\.id)
    }

    private func mutateRewards(_ mutate: (inout [Reward]) -> Void) {
        var next = rewards
        mutate(&next)
        next.sort { $0.createdAt < $1.createdAt }
        rewards = next
        rewardsByOwner[currentOwnerID] = next
        persist()
    }

    private func refreshCurrentRewards() {
        rewards = rewardsByOwner[currentOwnerID] ?? []
    }

    private func persist() {
        JSONFileStore.save(PersistedState(rewardsByOwner: rewardsByOwner), to: storageURL)
    }

    private func mergeRecords(local: [Reward], remote: [Reward]) -> [Reward] {
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

    private static func normalizePersistedRewards(_ rewardsByOwner: [String: [Reward]]) -> [String: [Reward]] {
        Dictionary(uniqueKeysWithValues: rewardsByOwner.map { ownerID, rewards in
            (ownerID, normalizeRewards(rewards))
        })
    }

    private static func normalizeRewards(_ rewards: [Reward]) -> [Reward] {
        var newestByID: [String: Reward] = [:]

        for reward in rewards {
            let normalized = Reward(
                id: CanonicalRecordID.normalize(reward.id),
                name: reward.name,
                description: reward.description,
                createdAt: reward.createdAt,
                updatedAt: reward.updatedAt,
                deletedAt: reward.deletedAt,
                maxFrequency: reward.maxFrequency,
                damageTier: reward.damageTier
            )

            if let existing = newestByID[normalized.id], existing.updatedAt > normalized.updatedAt {
                continue
            }

            newestByID[normalized.id] = normalized
        }

        return newestByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func notifySync(ids: [String]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .rewards, recordIDs: ids))
    }
}
