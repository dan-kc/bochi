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
        self.rewards = OwnerScopedRecordSupport.recordsForOwner(self.rewardsByOwner, ownerID: initialOwnerID)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        rewards = OwnerScopedRecordSupport.recordsForOwner(rewardsByOwner, ownerID: ownerID)
    }

    func migrateRewards(from sourceOwnerID: String, to destinationOwnerID: String) -> [RecordID] {
        let migratedIDs = OwnerScopedRecordSupport.migrateRecords(
            from: sourceOwnerID,
            to: destinationOwnerID,
            recordsByOwner: &rewardsByOwner
        )
        persist()
        refreshCurrentRewards()
        return migratedIDs
    }

    @discardableResult
    func addReward(
        id: RecordID? = nil,
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
        let canonicalID = id ?? RecordID()

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
        id: RecordID,
        name: String? = nil,
        description: String? = nil,
        maxFrequency: Double?? = nil,
        damageTier: RewardDamageTier?? = nil,
        updatedAt: Date = Date(),
        deletedAt: Date?? = nil,
        shouldNotifySync: Bool = true
    ) {
        let canonicalID = id
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

    func deleteReward(id: RecordID, deletedAt: Date = Date(), shouldNotifySync: Bool = true) {
        let canonicalID = id
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
            $0 = OwnerScopedRecordSupport.mergeRecords(local: $0, remote: remoteRewards)
        }
    }

    func getDirtyRewards(ids: Set<RecordID>) -> [Reward] {
        rewards.filter { ids.contains($0.id) }
    }

    func purgeDeletedRewards() {
        mutateRewards {
            $0.removeAll { $0.deletedAt != nil }
        }
    }

    func allRewardIDs() -> [RecordID] {
        rewards.map(\.id)
    }

    private func mutateRewards(_ mutate: (inout [Reward]) -> Void) {
        rewards = OwnerScopedRecordSupport.mutateRecords(
            currentRecords: rewards,
            ownerID: currentOwnerID,
            recordsByOwner: &rewardsByOwner,
            mutate: mutate
        )
        persist()
    }

    private func refreshCurrentRewards() {
        rewards = OwnerScopedRecordSupport.recordsForOwner(rewardsByOwner, ownerID: currentOwnerID)
    }

    private func persist() {
        JSONFileStore.save(PersistedState(rewardsByOwner: rewardsByOwner), to: storageURL)
    }

    private static func normalizePersistedRewards(_ rewardsByOwner: [String: [Reward]]) -> [String: [Reward]] {
        OwnerScopedRecordSupport.normalizePersistedRecords(rewardsByOwner) { reward in
            Reward(
                id: RecordID(rawValue: reward.id.rawValue),
                name: reward.name,
                description: reward.description,
                createdAt: reward.createdAt,
                updatedAt: reward.updatedAt,
                deletedAt: reward.deletedAt,
                maxFrequency: reward.maxFrequency,
                damageTier: reward.damageTier
            )
        }
    }

    private func notifySync(ids: [RecordID]) {
        SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .rewards, recordIDs: ids))
    }
}
