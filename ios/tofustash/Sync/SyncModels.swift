import Foundation

enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced
    case error(String)
}

struct SyncResponse: Decodable {
    let habits: [SyncHabitRecord]
    let trades: [SyncTradeRecord]
    let tags: [SyncTagRecord]
    let habitTags: [SyncHabitTagRecord]
    let rewards: [SyncRewardRecord]
    let rewardTags: [SyncRewardTagRecord]
    let balance: SyncBalanceRecord
    let serverTime: String
    let email: String?
    let isPremium: Bool
    let generalDifficulty: Double
}

struct SyncBalanceRecord: Decodable {
    let tofuBalance: Double
}

struct SyncHabitRecord: Codable {
    let id: String
    let name: String
    let description: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let minDailyFrequency: Double?
    let difficultyTier: HabitDifficultyTier?

    func toModel() -> Habit? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return Habit(
            id: id,
            name: name,
            description: description,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            frequency: minDailyFrequency,
            difficultyTier: difficultyTier
        )
    }

    static func from(_ habit: Habit) -> SyncHabitRecord {
        SyncHabitRecord(
            id: habit.id,
            name: habit.name,
            description: habit.description,
            createdAt: AppDateCoding.backendTimestamp(from: habit.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: habit.updatedAt),
            deletedAt: habit.deletedAt.map(AppDateCoding.backendTimestamp),
            minDailyFrequency: habit.frequency,
            difficultyTier: habit.difficultyTier
        )
    }
}

struct SyncTradeRecord: Codable {
    let id: String
    let habitId: String?
    let rewardId: String?
    let amount: Int
    let createdAt: String
    let updatedAt: String?
    let deletedAt: String?

    func toModel() -> Trade? {
        guard let createdAt = AppDateCoding.parseBackendTimestamp(createdAt) else {
            return nil
        }

        return Trade(
            id: id,
            habitId: habitId,
            rewardId: rewardId,
            amount: amount,
            createdAt: createdAt,
            updatedAt: AppDateCoding.parseBackendTimestamp(updatedAt) ?? createdAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt)
        )
    }

    static func from(_ trade: Trade) -> SyncTradeRecord {
        SyncTradeRecord(
            id: trade.id,
            habitId: trade.habitId,
            rewardId: trade.rewardId,
            amount: trade.amount,
            createdAt: AppDateCoding.backendTimestamp(from: trade.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: trade.updatedAt),
            deletedAt: trade.deletedAt.map(AppDateCoding.backendTimestamp)
        )
    }
}

struct SyncTagRecord: Codable {
    let id: String
    let name: String
    let colorHex: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    func toModel() -> Tag? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return Tag(
            id: id,
            name: name,
            colorHex: colorHex,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt)
        )
    }

    static func from(_ tag: Tag) -> SyncTagRecord {
        SyncTagRecord(
            id: tag.id,
            name: tag.name,
            colorHex: tag.colorHex,
            createdAt: AppDateCoding.backendTimestamp(from: tag.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: tag.updatedAt),
            deletedAt: tag.deletedAt.map(AppDateCoding.backendTimestamp)
        )
    }
}

struct SyncHabitTagRecord: Codable {
    let habitId: String
    let tagId: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    func toModel() -> HabitTag? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return HabitTag(
            habitId: habitId,
            tagId: tagId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt)
        )
    }

    static func from(_ habitTag: HabitTag) -> SyncHabitTagRecord {
        SyncHabitTagRecord(
            habitId: habitTag.habitId,
            tagId: habitTag.tagId,
            createdAt: AppDateCoding.backendTimestamp(from: habitTag.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: habitTag.updatedAt),
            deletedAt: habitTag.deletedAt.map(AppDateCoding.backendTimestamp)
        )
    }
}

struct SyncRewardRecord: Codable {
    let id: String
    let name: String
    let description: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let maxDailyFrequency: Double?
    let damageTier: RewardDamageTier?

    func toModel() -> Reward? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return Reward(
            id: id,
            name: name,
            description: description,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            maxFrequency: maxDailyFrequency,
            damageTier: damageTier
        )
    }

    static func from(_ reward: Reward) -> SyncRewardRecord {
        SyncRewardRecord(
            id: reward.id,
            name: reward.name,
            description: reward.description,
            createdAt: AppDateCoding.backendTimestamp(from: reward.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: reward.updatedAt),
            deletedAt: reward.deletedAt.map(AppDateCoding.backendTimestamp),
            maxDailyFrequency: reward.maxFrequency,
            damageTier: reward.damageTier
        )
    }
}

struct SyncRewardTagRecord: Codable {
    let rewardId: String
    let tagId: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    func toModel() -> RewardTag? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return RewardTag(
            rewardId: rewardId,
            tagId: tagId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt)
        )
    }

    static func from(_ rewardTag: RewardTag) -> SyncRewardTagRecord {
        SyncRewardTagRecord(
            rewardId: rewardTag.rewardId,
            tagId: rewardTag.tagId,
            createdAt: AppDateCoding.backendTimestamp(from: rewardTag.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: rewardTag.updatedAt),
            deletedAt: rewardTag.deletedAt.map(AppDateCoding.backendTimestamp)
        )
    }
}

struct SyncPushRequest: Encodable {
    let habits: [SyncHabitRecord]?
    let trades: [SyncTradeRecord]?
    let tags: [SyncTagRecord]?
    let habitTags: [SyncHabitTagRecord]?
    let rewards: [SyncRewardRecord]?
    let rewardTags: [SyncRewardTagRecord]?
    let generalDifficulty: Double?
}
