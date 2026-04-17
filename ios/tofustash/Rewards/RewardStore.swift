import Foundation

@Observable
@MainActor
final class RewardStore {
    private(set) var rewards: [Reward] = []

    var activeRewards: [Reward] {
        rewards.filter { $0.deletedAt == nil }
    }

    var rewardsSortedByDamage: [Reward] {
        activeRewards.sorted { lhs, rhs in
            switch (lhs.damageRank, rhs.damageRank) {
            case let (l?, r?):
                return l > r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.createdAt < rhs.createdAt
            }
        }
    }

    @discardableResult
    func addReward(
        id: String? = nil,
        name: String,
        description: String = "",
        maxFrequency: Double? = nil,
        damageRank: String? = nil
    ) -> Reward? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else {
            return nil
        }

        let now = Date()
        let reward = Reward(
            id: id ?? UUID().uuidString,
            name: trimmedName,
            description: description,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            maxFrequency: maxFrequency,
            damageRank: damageRank
        )

        rewards.append(reward)
        return reward
    }

    func updateReward(
        id: String,
        name: String? = nil,
        description: String? = nil,
        maxFrequency: Double?? = nil,
        damageRank: String?? = nil
    ) {
        guard let index = rewards.firstIndex(where: { $0.id == id }) else {
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

        rewards[index] = Reward(
            id: existing.id,
            name: newName,
            description: description ?? existing.description,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            deletedAt: existing.deletedAt,
            maxFrequency: maxFrequency ?? existing.maxFrequency,
            damageRank: damageRank ?? existing.damageRank
        )
    }

    func deleteReward(id: String) {
        guard let index = rewards.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existing = rewards[index]
        rewards[index] = Reward(
            id: existing.id,
            name: existing.name,
            description: existing.description,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            deletedAt: Date(),
            maxFrequency: existing.maxFrequency,
            damageRank: existing.damageRank
        )
    }
}
