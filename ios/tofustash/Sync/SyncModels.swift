import Foundation

enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced
    case error(String)
}

struct SyncResponse: Decodable {
    let tasks: [SyncTaskRecord]
    let habits: [SyncHabitRecord]
    let trades: [SyncTradeRecord]
    let tags: [SyncTagRecord]
    let taskTags: [SyncTaskTagRecord]
    let habitTags: [SyncHabitTagRecord]
    let rewards: [SyncRewardRecord]
    let rewardTags: [SyncRewardTagRecord]
    let balance: SyncBalanceRecord
    let serverCursor: String
    let serverTime: String
    let email: String?
    let isPremium: Bool
    let generalDifficulty: Double
}

struct SyncBalanceRecord: Decodable {
    let tofuBalance: Double
}

struct SyncTaskRecord: Codable {
    let id: String
    let name: String
    let description: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let completedAt: String?
    let difficultyTier: HabitDifficultyTier?
    let durationSeconds: Int?
    let skipConsequence: Int?
    let dueDate: String?

    func toModel() -> TaskItem? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return TaskItem(
            id: RecordID(id),
            name: name,
            description: description,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            completedAt: AppDateCoding.parseBackendTimestamp(completedAt),
            difficultyTier: difficultyTier,
            durationSeconds: durationSeconds,
            skipConsequence: skipConsequence,
            dueDate: AppDateCoding.parseBackendTimestamp(dueDate)
        )
    }

    static func from(_ task: TaskItem) -> SyncTaskRecord {
        SyncTaskRecord(
            id: task.id.rawValue,
            name: task.name,
            description: task.description,
            createdAt: AppDateCoding.backendTimestamp(from: task.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: task.updatedAt),
            deletedAt: task.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            completedAt: task.completedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            difficultyTier: task.difficultyTier,
            durationSeconds: task.durationSeconds,
            skipConsequence: task.skipConsequence,
            dueDate: task.dueDate.map { AppDateCoding.backendTimestamp(from: $0) }
        )
    }
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
    let durationSeconds: Int?
    let lockoutDurationSeconds: Int?
    let skipConsequence: Int?

    init(
        id: String,
        name: String,
        description: String,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        minDailyFrequency: Double?,
        difficultyTier: HabitDifficultyTier?,
        durationSeconds: Int? = nil,
        lockoutDurationSeconds: Int? = nil,
        skipConsequence: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.minDailyFrequency = minDailyFrequency
        self.difficultyTier = difficultyTier
        self.durationSeconds = durationSeconds
        self.lockoutDurationSeconds = lockoutDurationSeconds
        self.skipConsequence = skipConsequence
    }

    func toModel() -> Habit? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return Habit(
            id: RecordID(id),
            name: name,
            description: description,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            frequency: minDailyFrequency,
            difficultyTier: difficultyTier,
            durationSeconds: durationSeconds,
            lockoutDurationSeconds: lockoutDurationSeconds,
            skipConsequence: skipConsequence
        )
    }

    static func from(_ habit: Habit) -> SyncHabitRecord {
        SyncHabitRecord(
            id: habit.id.rawValue,
            name: habit.name,
            description: habit.description,
            createdAt: AppDateCoding.backendTimestamp(from: habit.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: habit.updatedAt),
            deletedAt: habit.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            minDailyFrequency: habit.frequency,
            difficultyTier: habit.difficultyTier,
            durationSeconds: habit.durationSeconds,
            lockoutDurationSeconds: habit.lockoutDurationSeconds,
            skipConsequence: habit.skipConsequence
        )
    }
}

struct SyncTradeRecord: Codable {
    let id: String
    let taskId: String?
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
            id: RecordID(id),
            taskId: taskId.map { RecordID($0) },
            habitId: habitId.map { RecordID($0) },
            rewardId: rewardId.map { RecordID($0) },
            amount: amount,
            createdAt: createdAt,
            updatedAt: AppDateCoding.parseBackendTimestamp(updatedAt) ?? createdAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt)
        )
    }

    static func from(_ trade: Trade) -> SyncTradeRecord {
        SyncTradeRecord(
            id: trade.id.rawValue,
            taskId: trade.taskId?.rawValue,
            habitId: trade.habitId?.rawValue,
            rewardId: trade.rewardId?.rawValue,
            amount: trade.amount,
            createdAt: AppDateCoding.backendTimestamp(from: trade.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: trade.updatedAt),
            deletedAt: trade.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) }
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
            id: RecordID(id),
            name: name,
            colorHex: colorHex,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt)
        )
    }

    static func from(_ tag: Tag) -> SyncTagRecord {
        SyncTagRecord(
            id: tag.id.rawValue,
            name: tag.name,
            colorHex: tag.colorHex,
            createdAt: AppDateCoding.backendTimestamp(from: tag.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: tag.updatedAt),
            deletedAt: tag.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) }
        )
    }
}

struct SyncTaskTagRecord: Codable {
    let taskId: String
    let tagId: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    func toModel() -> TaskTag? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return TaskTag(
            taskId: RecordID(taskId),
            tagId: RecordID(tagId),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt)
        )
    }

    static func from(_ taskTag: TaskTag) -> SyncTaskTagRecord {
        SyncTaskTagRecord(
            taskId: taskTag.taskId.rawValue,
            tagId: taskTag.tagId.rawValue,
            createdAt: AppDateCoding.backendTimestamp(from: taskTag.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: taskTag.updatedAt),
            deletedAt: taskTag.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) }
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
            habitId: RecordID(habitId),
            tagId: RecordID(tagId),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt)
        )
    }

    static func from(_ habitTag: HabitTag) -> SyncHabitTagRecord {
        SyncHabitTagRecord(
            habitId: habitTag.habitId.rawValue,
            tagId: habitTag.tagId.rawValue,
            createdAt: AppDateCoding.backendTimestamp(from: habitTag.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: habitTag.updatedAt),
            deletedAt: habitTag.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) }
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
            id: RecordID(id),
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
            id: reward.id.rawValue,
            name: reward.name,
            description: reward.description,
            createdAt: AppDateCoding.backendTimestamp(from: reward.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: reward.updatedAt),
            deletedAt: reward.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
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
            rewardId: RecordID(rewardId),
            tagId: RecordID(tagId),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt)
        )
    }

    static func from(_ rewardTag: RewardTag) -> SyncRewardTagRecord {
        SyncRewardTagRecord(
            rewardId: rewardTag.rewardId.rawValue,
            tagId: rewardTag.tagId.rawValue,
            createdAt: AppDateCoding.backendTimestamp(from: rewardTag.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: rewardTag.updatedAt),
            deletedAt: rewardTag.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) }
        )
    }
}

struct SyncPushRequest: Encodable {
    let tasks: [SyncTaskRecord]?
    let habits: [SyncHabitRecord]?
    let trades: [SyncTradeRecord]?
    let tags: [SyncTagRecord]?
    let taskTags: [SyncTaskTagRecord]?
    let habitTags: [SyncHabitTagRecord]?
    let rewards: [SyncRewardRecord]?
    let rewardTags: [SyncRewardTagRecord]?
    let generalDifficulty: Double?
}
