import Foundation

// Sync flow: shared UI status and backend DTOs used by pull, push, mapping, and
// reconciliation helpers.
enum SyncStatus: Equatable {
    case idle
    case syncing
    case synced
    case error(String)
}

private extension KeyedDecodingContainer {
    func decodeBackendSignedInt(forKey key: Key) throws -> Int {
        let value = try decode(Int.self, forKey: key)
        try BackendIntegerContract.validateSigned(value, fieldName: key.stringValue)
        return value
    }

    func decodeBackendOptionalSignedInt(forKey key: Key) throws -> Int? {
        guard let value = try decodeIfPresent(Int.self, forKey: key) else { return nil }
        try BackendIntegerContract.validateSigned(value, fieldName: key.stringValue)
        return value
    }

    func decodeBackendNonNegativeInt(forKey key: Key) throws -> Int {
        let value = try decode(Int.self, forKey: key)
        try BackendIntegerContract.validateNonNegative(value, fieldName: key.stringValue)
        return value
    }

    func decodeBackendPositiveInt(forKey key: Key) throws -> Int {
        let value = try decode(Int.self, forKey: key)
        try BackendIntegerContract.validatePositive(value, fieldName: key.stringValue)
        return value
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeBackendSignedInt(_ value: Int, forKey key: Key) throws {
        try BackendIntegerContract.validateSigned(value, fieldName: key.stringValue)
        try encode(value, forKey: key)
    }

    mutating func encodeBackendOptionalSignedInt(_ value: Int?, forKey key: Key) throws {
        guard let value else {
            try encodeNil(forKey: key)
            return
        }
        try BackendIntegerContract.validateSigned(value, fieldName: key.stringValue)
        try encode(value, forKey: key)
    }

    mutating func encodeBackendNonNegativeInt(_ value: Int, forKey key: Key) throws {
        try BackendIntegerContract.validateNonNegative(value, fieldName: key.stringValue)
        try encode(value, forKey: key)
    }

    mutating func encodeBackendPositiveInt(_ value: Int, forKey key: Key) throws {
        try BackendIntegerContract.validatePositive(value, fieldName: key.stringValue)
        try encode(value, forKey: key)
    }
}

nonisolated struct SyncResponse: Decodable {
    let timers: [SyncTimerRecord]
    let tasks: [SyncTaskRecord]
    let recurringTasks: [SyncRecurringTaskRecord]
    let trades: [SyncTradeRecord]
    let tags: [SyncTagRecord]
    let taskTags: [SyncTaskTagRecord]
    let taskTaskDependencies: [SyncTaskTaskDependencyRecord]
    let taskRecurringTaskDependencies: [SyncTaskRecurringTaskDependencyRecord]
    let recurringTaskTags: [SyncRecurringTaskTagRecord]
    let rewards: [SyncRewardRecord]
    let rewardTaskDependencies: [SyncRewardTaskDependencyRecord]
    let rewardRecurringTaskDependencies: [SyncRewardRecurringTaskDependencyRecord]
    let rewardTags: [SyncRewardTagRecord]
    let balance: SyncBalanceRecord
    let serverCursor: String
    let serverTime: String
    let email: String?
    let isPremium: Bool
    let themePalettes: SyncThemePalettes

    enum CodingKeys: String, CodingKey {
        case timers
        case tasks
        case recurringTasks
        case trades
        case tags
        case taskTags
        case taskTaskDependencies
        case taskRecurringTaskDependencies
        case recurringTaskTags
        case rewards
        case rewardTaskDependencies
        case rewardRecurringTaskDependencies
        case rewardTags
        case balance
        case serverCursor
        case serverTime
        case email
        case isPremium
        case themePalettes
    }

    init(
        timers: [SyncTimerRecord],
        tasks: [SyncTaskRecord],
        recurringTasks: [SyncRecurringTaskRecord],
        trades: [SyncTradeRecord],
        tags: [SyncTagRecord],
        taskTags: [SyncTaskTagRecord],
        taskTaskDependencies: [SyncTaskTaskDependencyRecord],
        taskRecurringTaskDependencies: [SyncTaskRecurringTaskDependencyRecord],
        recurringTaskTags: [SyncRecurringTaskTagRecord],
        rewards: [SyncRewardRecord],
        rewardTaskDependencies: [SyncRewardTaskDependencyRecord],
        rewardRecurringTaskDependencies: [SyncRewardRecurringTaskDependencyRecord],
        rewardTags: [SyncRewardTagRecord],
        balance: SyncBalanceRecord,
        serverCursor: String,
        serverTime: String,
        email: String?,
        isPremium: Bool,
        themePalettes: SyncThemePalettes
    ) {
        self.timers = timers
        self.tasks = tasks
        self.recurringTasks = recurringTasks
        self.trades = trades
        self.tags = tags
        self.taskTags = taskTags
        self.taskTaskDependencies = taskTaskDependencies
        self.taskRecurringTaskDependencies = taskRecurringTaskDependencies
        self.recurringTaskTags = recurringTaskTags
        self.rewards = rewards
        self.rewardTaskDependencies = rewardTaskDependencies
        self.rewardRecurringTaskDependencies = rewardRecurringTaskDependencies
        self.rewardTags = rewardTags
        self.balance = balance
        self.serverCursor = serverCursor
        self.serverTime = serverTime
        self.email = email
        self.isPremium = isPremium
        self.themePalettes = themePalettes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timers = try container.decode([SyncTimerRecord].self, forKey: .timers)
        tasks = try container.decode([SyncTaskRecord].self, forKey: .tasks)
        recurringTasks = try container.decode([SyncRecurringTaskRecord].self, forKey: .recurringTasks)
        trades = try container.decode([SyncTradeRecord].self, forKey: .trades)
        tags = try container.decode([SyncTagRecord].self, forKey: .tags)
        taskTags = try container.decode([SyncTaskTagRecord].self, forKey: .taskTags)
        taskTaskDependencies = try container.decode([SyncTaskTaskDependencyRecord].self, forKey: .taskTaskDependencies)
        taskRecurringTaskDependencies = try container.decode([SyncTaskRecurringTaskDependencyRecord].self, forKey: .taskRecurringTaskDependencies)
        recurringTaskTags = try container.decode([SyncRecurringTaskTagRecord].self, forKey: .recurringTaskTags)
        rewards = try container.decode([SyncRewardRecord].self, forKey: .rewards)
        rewardTaskDependencies = try container.decode([SyncRewardTaskDependencyRecord].self, forKey: .rewardTaskDependencies)
        rewardRecurringTaskDependencies = try container.decode([SyncRewardRecurringTaskDependencyRecord].self, forKey: .rewardRecurringTaskDependencies)
        rewardTags = try container.decode([SyncRewardTagRecord].self, forKey: .rewardTags)
        balance = try container.decode(SyncBalanceRecord.self, forKey: .balance)
        serverCursor = try container.decode(String.self, forKey: .serverCursor)
        serverTime = try container.decode(String.self, forKey: .serverTime)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        isPremium = try container.decode(Bool.self, forKey: .isPremium)
        themePalettes = try container.decode(SyncThemePalettes.self, forKey: .themePalettes)
    }
}

struct SyncBalanceRecord: Decodable {
    let pointBalance: Int
}

struct SyncTimerRecord: Codable {
    let id: String
    let name: String
    let intervals: [TimerInterval]
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let serverRevision: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case intervals
        case createdAt
        case updatedAt
        case deletedAt
        case serverRevision
    }

    init(
        id: String,
        name: String,
        intervals: [TimerInterval],
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        serverRevision: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.intervals = intervals
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(intervals, forKey: .intervals)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    func toModel() -> BochiTimer? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return BochiTimer(
            id: RecordID(id),
            name: name,
            intervals: intervals,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            serverRevision: serverRevision
        )
    }

    static func from(_ timer: BochiTimer) -> SyncTimerRecord {
        SyncTimerRecord(
            id: timer.id.rawValue,
            name: timer.name,
            intervals: timer.intervals,
            createdAt: AppDateCoding.backendTimestamp(from: timer.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: timer.updatedAt),
            deletedAt: timer.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            serverRevision: timer.serverRevision
        )
    }
}

struct SyncThemePalettes: Codable, Equatable {
    let main: BochiThemePaletteName
    let accent: BochiThemeAccentChoice

    static let `default` = SyncThemePalettes(
        main: .porcelain,
        accent: .semantic
    )

    init(
        main: BochiThemePaletteName,
        accent: BochiThemeAccentChoice
    ) {
        self.main = main
        self.accent = accent
    }

    init(preferences: BochiThemePalettePreferences) {
        self.init(
            main: preferences.main,
            accent: preferences.accent
        )
    }

    func toPreferences() -> BochiThemePalettePreferences {
        BochiThemePalettePreferences(
            main: main,
            accent: accent
        )
    }
}

struct SyncTaskRecord: Codable {
    let id: String
    let name: String
    let description: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let basePrice: Int
    let dueDate: String?
    let pinned: Bool
    let hidden: Bool
    let timerMode: String?
    let timerId: String?
    let serverRevision: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case createdAt
        case updatedAt
        case deletedAt
        case basePrice
        case dueDate
        case pinned
        case hidden
        case timerMode
        case timerId
        case serverRevision
    }

    init(
        id: String,
        name: String,
        description: String,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        basePrice: Int,
        dueDate: String?,
        pinned: Bool = false,
        hidden: Bool = false,
        timerMode: String? = nil,
        timerId: String? = nil,
        serverRevision: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.basePrice = basePrice
        self.dueDate = dueDate
        self.pinned = pinned
        self.hidden = hidden
        self.timerMode = timerMode
        self.timerId = timerId
        self.serverRevision = serverRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        self.basePrice = try container.decodeBackendNonNegativeInt(forKey: .basePrice)
        self.dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
        self.pinned = try container.decode(Bool.self, forKey: .pinned)
        self.hidden = try container.decode(Bool.self, forKey: .hidden)
        self.timerMode = try container.decodeIfPresent(String.self, forKey: .timerMode)
        self.timerId = try container.decodeIfPresent(String.self, forKey: .timerId)
        self.serverRevision = try container.decodeIfPresent(Int64.self, forKey: .serverRevision)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encodeBackendNonNegativeInt(basePrice, forKey: .basePrice)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(pinned, forKey: .pinned)
        try container.encode(hidden, forKey: .hidden)
        try container.encodeIfPresent(timerMode, forKey: .timerMode)
        try container.encodeIfPresent(timerId, forKey: .timerId)
    }

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
            basePrice: basePrice,
            dueDate: AppDateCoding.parseBackendTimestamp(dueDate),
            pinned: pinned,
            hidden: hidden,
            timerSelection: EntityTimerSelection.from(
                mode: timerMode,
                timerID: timerId.map { RecordID($0) }
            ),
            serverRevision: serverRevision
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
            basePrice: task.basePrice,
            dueDate: task.dueDate.map { AppDateCoding.backendTimestamp(from: $0) },
            pinned: task.pinned,
            hidden: task.hidden,
            timerMode: task.timerSelection.modeValue,
            timerId: task.timerSelection.timerID?.rawValue,
            serverRevision: task.serverRevision
        )
    }
}

struct SyncRecurringTaskRecord: Codable {
    let id: String
    let name: String
    let description: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let minDailyFrequency: Double?
    let lockoutDurationSeconds: Int?
    let basePrice: Int
    let pinned: Bool
    let hidden: Bool
    let timerMode: String?
    let timerId: String?
    let serverRevision: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case createdAt
        case updatedAt
        case deletedAt
        case minDailyFrequency
        case lockoutDurationSeconds
        case basePrice
        case pinned
        case hidden
        case timerMode
        case timerId
        case serverRevision
    }

    init(
        id: String,
        name: String,
        description: String,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        minDailyFrequency: Double?,
        lockoutDurationSeconds: Int? = nil,
        basePrice: Int,
        pinned: Bool = false,
        hidden: Bool = false,
        timerMode: String? = nil,
        timerId: String? = nil,
        serverRevision: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.minDailyFrequency = minDailyFrequency
        self.lockoutDurationSeconds = lockoutDurationSeconds
        self.basePrice = basePrice
        self.pinned = pinned
        self.hidden = hidden
        self.timerMode = timerMode
        self.timerId = timerId
        self.serverRevision = serverRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        self.minDailyFrequency = try container.decodeIfPresent(Double.self, forKey: .minDailyFrequency)
        self.lockoutDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .lockoutDurationSeconds)
        self.basePrice = try container.decodeBackendNonNegativeInt(forKey: .basePrice)
        self.pinned = try container.decode(Bool.self, forKey: .pinned)
        self.hidden = try container.decode(Bool.self, forKey: .hidden)
        self.timerMode = try container.decodeIfPresent(String.self, forKey: .timerMode)
        self.timerId = try container.decodeIfPresent(String.self, forKey: .timerId)
        self.serverRevision = try container.decodeIfPresent(Int64.self, forKey: .serverRevision)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encodeIfPresent(minDailyFrequency, forKey: .minDailyFrequency)
        try container.encodeIfPresent(lockoutDurationSeconds, forKey: .lockoutDurationSeconds)
        try container.encodeBackendNonNegativeInt(basePrice, forKey: .basePrice)
        try container.encode(pinned, forKey: .pinned)
        try container.encode(hidden, forKey: .hidden)
        try container.encodeIfPresent(timerMode, forKey: .timerMode)
        try container.encodeIfPresent(timerId, forKey: .timerId)
    }

    func toModel() -> RecurringTask? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return RecurringTask(
            id: RecordID(id),
            name: name,
            description: description,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            frequency: minDailyFrequency,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: basePrice,
            pinned: pinned,
            hidden: hidden,
            timerSelection: EntityTimerSelection.from(
                mode: timerMode,
                timerID: timerId.map { RecordID($0) }
            ),
            serverRevision: serverRevision
        )
    }

    static func from(_ recurringTask: RecurringTask) -> SyncRecurringTaskRecord {
        SyncRecurringTaskRecord(
            id: recurringTask.id.rawValue,
            name: recurringTask.name,
            description: recurringTask.description,
            createdAt: AppDateCoding.backendTimestamp(from: recurringTask.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: recurringTask.updatedAt),
            deletedAt: recurringTask.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            minDailyFrequency: recurringTask.frequency,
            lockoutDurationSeconds: recurringTask.lockoutDurationSeconds,
            basePrice: recurringTask.basePrice,
            pinned: recurringTask.pinned,
            hidden: recurringTask.hidden,
            timerMode: recurringTask.timerSelection.modeValue,
            timerId: recurringTask.timerSelection.timerID?.rawValue,
            serverRevision: recurringTask.serverRevision
        )
    }
}

struct SyncTradeRecord: Codable {
    let id: String
    let taskId: String?
    let recurringTaskId: String?
    let rewardId: String?
    let sourceName: String?
    let amount: Int
    let vaultAmountMicro: Int?
    let adjustmentBaseAmount: Int?
    let oneTimeAdjustmentMultiplier: Double?
    let tradeKind: TradeKind?
    let vaultInterestHour: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let refundsTradeId: String?
    let serverRevision: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId
        case recurringTaskId
        case rewardId
        case sourceName
        case amount
        case vaultAmountMicro
        case adjustmentBaseAmount
        case oneTimeAdjustmentMultiplier
        case tradeKind
        case vaultInterestHour
        case createdAt
        case updatedAt
        case deletedAt
        case refundsTradeId
        case serverRevision
    }

    init(
        id: String,
        taskId: String?,
        recurringTaskId: String?,
        rewardId: String?,
        sourceName: String?,
        amount: Int,
        vaultAmountMicro: Int? = nil,
        adjustmentBaseAmount: Int? = nil,
        oneTimeAdjustmentMultiplier: Double? = nil,
        tradeKind: TradeKind? = nil,
        vaultInterestHour: String? = nil,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        refundsTradeId: String?,
        serverRevision: Int64? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.recurringTaskId = recurringTaskId
        self.rewardId = rewardId
        self.sourceName = sourceName
        self.amount = amount
        self.vaultAmountMicro = vaultAmountMicro
        self.adjustmentBaseAmount = adjustmentBaseAmount
        self.oneTimeAdjustmentMultiplier = oneTimeAdjustmentMultiplier
        self.tradeKind = tradeKind
        self.vaultInterestHour = vaultInterestHour
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.refundsTradeId = refundsTradeId
        self.serverRevision = serverRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.taskId = try container.decodeIfPresent(String.self, forKey: .taskId)
        self.recurringTaskId = try container.decodeIfPresent(String.self, forKey: .recurringTaskId)
        self.rewardId = try container.decodeIfPresent(String.self, forKey: .rewardId)
        self.sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        self.amount = try container.decodeBackendSignedInt(forKey: .amount)
        self.vaultAmountMicro = try container.decodeIfPresent(Int.self, forKey: .vaultAmountMicro)
        self.adjustmentBaseAmount = try container.decodeBackendOptionalSignedInt(forKey: .adjustmentBaseAmount)
        self.oneTimeAdjustmentMultiplier = try container.decodeIfPresent(Double.self, forKey: .oneTimeAdjustmentMultiplier)
        self.tradeKind = try container.decodeIfPresent(TradeKind.self, forKey: .tradeKind)
        self.vaultInterestHour = try container.decodeIfPresent(String.self, forKey: .vaultInterestHour)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        self.refundsTradeId = try container.decodeIfPresent(String.self, forKey: .refundsTradeId)
        self.serverRevision = try container.decodeIfPresent(Int64.self, forKey: .serverRevision)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(taskId, forKey: .taskId)
        try container.encodeIfPresent(recurringTaskId, forKey: .recurringTaskId)
        try container.encodeIfPresent(rewardId, forKey: .rewardId)
        try container.encodeIfPresent(sourceName, forKey: .sourceName)
        try container.encodeBackendSignedInt(amount, forKey: .amount)
        try container.encodeIfPresent(vaultAmountMicro, forKey: .vaultAmountMicro)
        try container.encodeBackendOptionalSignedInt(adjustmentBaseAmount, forKey: .adjustmentBaseAmount)
        try container.encodeIfPresent(oneTimeAdjustmentMultiplier, forKey: .oneTimeAdjustmentMultiplier)
        try container.encodeIfPresent(tradeKind, forKey: .tradeKind)
        try container.encodeIfPresent(vaultInterestHour, forKey: .vaultInterestHour)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encodeIfPresent(refundsTradeId, forKey: .refundsTradeId)
    }

    func toModel() -> Trade? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return Trade(
            id: RecordID(id),
            taskId: taskId.map { RecordID($0) },
            recurringTaskId: recurringTaskId.map { RecordID($0) },
            rewardId: rewardId.map { RecordID($0) },
            sourceName: sourceName,
            amount: amount,
            vaultAmountMicro: vaultAmountMicro,
            adjustmentBaseAmount: adjustmentBaseAmount,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            tradeKind: tradeKind,
            vaultInterestHour: AppDateCoding.parseBackendTimestamp(vaultInterestHour),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            refundsTradeId: refundsTradeId.map { RecordID($0) },
            serverRevision: serverRevision
        )
    }

    static func from(_ trade: Trade) -> SyncTradeRecord {
        SyncTradeRecord(
            id: trade.id.rawValue,
            taskId: trade.taskId?.rawValue,
            recurringTaskId: trade.recurringTaskId?.rawValue,
            rewardId: trade.rewardId?.rawValue,
            sourceName: trade.sourceName,
            amount: trade.amount,
            vaultAmountMicro: trade.vaultAmountMicro,
            adjustmentBaseAmount: trade.adjustmentBaseAmount,
            oneTimeAdjustmentMultiplier: trade.oneTimeAdjustmentMultiplier,
            tradeKind: trade.tradeKind,
            vaultInterestHour: trade.vaultInterestHour.map { AppDateCoding.backendTimestamp(from: $0) },
            createdAt: AppDateCoding.backendTimestamp(from: trade.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: trade.updatedAt),
            deletedAt: trade.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            refundsTradeId: trade.refundsTradeId?.rawValue,
            serverRevision: trade.serverRevision
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
    let serverRevision: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex
        case createdAt
        case updatedAt
        case deletedAt
        case serverRevision
    }

    init(
        id: String,
        name: String,
        colorHex: String,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        serverRevision: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

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
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            serverRevision: serverRevision
        )
    }

    static func from(_ tag: Tag) -> SyncTagRecord {
        SyncTagRecord(
            id: tag.id.rawValue,
            name: tag.name,
            colorHex: tag.colorHex,
            createdAt: AppDateCoding.backendTimestamp(from: tag.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: tag.updatedAt),
            deletedAt: tag.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            serverRevision: tag.serverRevision
        )
    }
}

struct SyncTaskTagRecord: Codable {
    let taskId: String
    let tagId: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let serverRevision: Int64?

    init(
        taskId: String,
        tagId: String,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        serverRevision: Int64? = nil
    ) {
        self.taskId = taskId
        self.tagId = tagId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }

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
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            serverRevision: serverRevision
        )
    }

    static func from(_ taskTag: TaskTag) -> SyncTaskTagRecord {
        SyncTaskTagRecord(
            taskId: taskTag.taskId.rawValue,
            tagId: taskTag.tagId.rawValue,
            createdAt: AppDateCoding.backendTimestamp(from: taskTag.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: taskTag.updatedAt),
            deletedAt: taskTag.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            serverRevision: taskTag.serverRevision
        )
    }
}

struct SyncTaskTaskDependencyRecord: Codable {
    let taskId: String
    let dependsOnTaskId: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let serverRevision: Int64?

    init(
        taskId: String,
        dependsOnTaskId: String,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        serverRevision: Int64? = nil
    ) {
        self.taskId = taskId
        self.dependsOnTaskId = dependsOnTaskId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }

    func toModel() -> TaskTaskDependency? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return TaskTaskDependency(
            taskId: RecordID(taskId),
            dependsOnTaskId: RecordID(dependsOnTaskId),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            serverRevision: serverRevision
        )
    }

    static func from(_ dependency: TaskTaskDependency) -> SyncTaskTaskDependencyRecord {
        SyncTaskTaskDependencyRecord(
            taskId: dependency.taskId.rawValue,
            dependsOnTaskId: dependency.dependsOnTaskId.rawValue,
            createdAt: AppDateCoding.backendTimestamp(from: dependency.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: dependency.updatedAt),
            deletedAt: dependency.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            serverRevision: dependency.serverRevision
        )
    }
}

struct SyncTaskRecurringTaskDependencyRecord: Codable {
    let taskId: String
    let recurringTaskId: String
    let requiredCompletions: Int
    let baselineCompletionCount: Int
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let serverRevision: Int64?

    enum CodingKeys: String, CodingKey {
        case taskId
        case recurringTaskId
        case requiredCompletions
        case baselineCompletionCount
        case createdAt
        case updatedAt
        case deletedAt
        case serverRevision
    }

    init(
        taskId: String,
        recurringTaskId: String,
        requiredCompletions: Int,
        baselineCompletionCount: Int,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        serverRevision: Int64? = nil
    ) {
        self.taskId = taskId
        self.recurringTaskId = recurringTaskId
        self.requiredCompletions = requiredCompletions
        self.baselineCompletionCount = baselineCompletionCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.taskId = try container.decode(String.self, forKey: .taskId)
        self.recurringTaskId = try container.decode(String.self, forKey: .recurringTaskId)
        self.requiredCompletions = try container.decodeBackendPositiveInt(forKey: .requiredCompletions)
        self.baselineCompletionCount = try container.decodeBackendNonNegativeInt(forKey: .baselineCompletionCount)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        self.serverRevision = try container.decodeIfPresent(Int64.self, forKey: .serverRevision)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(taskId, forKey: .taskId)
        try container.encode(recurringTaskId, forKey: .recurringTaskId)
        try container.encodeBackendPositiveInt(requiredCompletions, forKey: .requiredCompletions)
        try container.encodeBackendNonNegativeInt(baselineCompletionCount, forKey: .baselineCompletionCount)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    func toModel() -> TaskRecurringTaskDependency? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return TaskRecurringTaskDependency(
            taskId: RecordID(taskId),
            recurringTaskId: RecordID(recurringTaskId),
            requiredCompletions: requiredCompletions,
            baselineCompletionCount: baselineCompletionCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            serverRevision: serverRevision
        )
    }

    static func from(_ dependency: TaskRecurringTaskDependency) -> SyncTaskRecurringTaskDependencyRecord {
        SyncTaskRecurringTaskDependencyRecord(
            taskId: dependency.taskId.rawValue,
            recurringTaskId: dependency.recurringTaskId.rawValue,
            requiredCompletions: dependency.requiredCompletions,
            baselineCompletionCount: dependency.baselineCompletionCount,
            createdAt: AppDateCoding.backendTimestamp(from: dependency.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: dependency.updatedAt),
            deletedAt: dependency.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            serverRevision: dependency.serverRevision
        )
    }
}

struct SyncRecurringTaskTagRecord: Codable {
    let recurringTaskId: String
    let tagId: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let serverRevision: Int64?

    init(
        recurringTaskId: String,
        tagId: String,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        serverRevision: Int64? = nil
    ) {
        self.recurringTaskId = recurringTaskId
        self.tagId = tagId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }

    func toModel() -> RecurringTaskTag? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return RecurringTaskTag(
            recurringTaskId: RecordID(recurringTaskId),
            tagId: RecordID(tagId),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            serverRevision: serverRevision
        )
    }

    static func from(_ recurringTaskTag: RecurringTaskTag) -> SyncRecurringTaskTagRecord {
        SyncRecurringTaskTagRecord(
            recurringTaskId: recurringTaskTag.recurringTaskId.rawValue,
            tagId: recurringTaskTag.tagId.rawValue,
            createdAt: AppDateCoding.backendTimestamp(from: recurringTaskTag.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: recurringTaskTag.updatedAt),
            deletedAt: recurringTaskTag.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            serverRevision: recurringTaskTag.serverRevision
        )
    }
}

struct SyncRewardRecord: Codable {
    let id: String
    let recurring: Bool
    let name: String
    let description: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let maxDailyFrequency: Double?
    let lockoutDurationSeconds: Int?
    let basePrice: Int
    let pinned: Bool
    let hidden: Bool
    let timerMode: String?
    let timerId: String?
    let serverRevision: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case recurring
        case name
        case description
        case createdAt
        case updatedAt
        case deletedAt
        case maxDailyFrequency
        case lockoutDurationSeconds
        case basePrice
        case pinned
        case hidden
        case timerMode
        case timerId
        case serverRevision
    }

    init(
        id: String,
        recurring: Bool = true,
        name: String,
        description: String,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        maxDailyFrequency: Double?,
        lockoutDurationSeconds: Int? = nil,
        basePrice: Int,
        pinned: Bool = false,
        hidden: Bool = false,
        timerMode: String? = nil,
        timerId: String? = nil,
        serverRevision: Int64? = nil
    ) {
        self.id = id
        self.recurring = recurring
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.maxDailyFrequency = maxDailyFrequency
        self.lockoutDurationSeconds = lockoutDurationSeconds
        self.basePrice = basePrice
        self.pinned = pinned
        self.hidden = hidden
        self.timerMode = timerMode
        self.timerId = timerId
        self.serverRevision = serverRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.recurring = try container.decode(Bool.self, forKey: .recurring)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        self.maxDailyFrequency = try container.decodeIfPresent(Double.self, forKey: .maxDailyFrequency)
        self.lockoutDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .lockoutDurationSeconds)
        self.basePrice = try container.decodeBackendNonNegativeInt(forKey: .basePrice)
        self.pinned = try container.decode(Bool.self, forKey: .pinned)
        self.hidden = try container.decode(Bool.self, forKey: .hidden)
        self.timerMode = try container.decodeIfPresent(String.self, forKey: .timerMode)
        self.timerId = try container.decodeIfPresent(String.self, forKey: .timerId)
        self.serverRevision = try container.decodeIfPresent(Int64.self, forKey: .serverRevision)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(recurring, forKey: .recurring)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encodeIfPresent(maxDailyFrequency, forKey: .maxDailyFrequency)
        try container.encodeIfPresent(lockoutDurationSeconds, forKey: .lockoutDurationSeconds)
        try container.encodeBackendNonNegativeInt(basePrice, forKey: .basePrice)
        try container.encode(pinned, forKey: .pinned)
        try container.encode(hidden, forKey: .hidden)
        try container.encodeIfPresent(timerMode, forKey: .timerMode)
        try container.encodeIfPresent(timerId, forKey: .timerId)
    }

    func toModel() -> Reward? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return Reward(
            id: RecordID(id),
            recurring: recurring,
            name: name,
            description: description,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            maxFrequency: maxDailyFrequency,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: basePrice,
            pinned: pinned,
            hidden: hidden,
            timerSelection: EntityTimerSelection.from(
                mode: timerMode,
                timerID: timerId.map { RecordID($0) }
            ),
            serverRevision: serverRevision
        )
    }

    static func from(_ reward: Reward) -> SyncRewardRecord {
        SyncRewardRecord(
            id: reward.id.rawValue,
            recurring: reward.recurring,
            name: reward.name,
            description: reward.description,
            createdAt: AppDateCoding.backendTimestamp(from: reward.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: reward.updatedAt),
            deletedAt: reward.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            maxDailyFrequency: reward.recurring ? reward.maxFrequency : nil,
            lockoutDurationSeconds: reward.lockoutDurationSeconds,
            basePrice: reward.basePrice,
            pinned: reward.pinned,
            hidden: reward.hidden,
            timerMode: reward.timerSelection.modeValue,
            timerId: reward.timerSelection.timerID?.rawValue,
            serverRevision: reward.serverRevision
        )
    }
}

struct SyncRewardTaskDependencyRecord: Codable {
    let rewardId: String
    let dependsOnTaskId: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let serverRevision: Int64?

    init(
        rewardId: String,
        dependsOnTaskId: String,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        serverRevision: Int64? = nil
    ) {
        self.rewardId = rewardId
        self.dependsOnTaskId = dependsOnTaskId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }

    func toModel() -> RewardTaskDependency? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return RewardTaskDependency(
            rewardId: RecordID(rewardId),
            dependsOnTaskId: RecordID(dependsOnTaskId),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            serverRevision: serverRevision
        )
    }

    static func from(_ dependency: RewardTaskDependency) -> SyncRewardTaskDependencyRecord {
        SyncRewardTaskDependencyRecord(
            rewardId: dependency.rewardId.rawValue,
            dependsOnTaskId: dependency.dependsOnTaskId.rawValue,
            createdAt: AppDateCoding.backendTimestamp(from: dependency.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: dependency.updatedAt),
            deletedAt: dependency.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            serverRevision: dependency.serverRevision
        )
    }
}

struct SyncRewardRecurringTaskDependencyRecord: Codable {
    let rewardId: String
    let recurringTaskId: String
    let requiredCompletions: Int
    let baselineCompletionCount: Int
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let serverRevision: Int64?

    enum CodingKeys: String, CodingKey {
        case rewardId
        case recurringTaskId
        case requiredCompletions
        case baselineCompletionCount
        case createdAt
        case updatedAt
        case deletedAt
        case serverRevision
    }

    init(
        rewardId: String,
        recurringTaskId: String,
        requiredCompletions: Int,
        baselineCompletionCount: Int,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        serverRevision: Int64? = nil
    ) {
        self.rewardId = rewardId
        self.recurringTaskId = recurringTaskId
        self.requiredCompletions = requiredCompletions
        self.baselineCompletionCount = baselineCompletionCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rewardId = try container.decode(String.self, forKey: .rewardId)
        self.recurringTaskId = try container.decode(String.self, forKey: .recurringTaskId)
        self.requiredCompletions = try container.decodeBackendPositiveInt(forKey: .requiredCompletions)
        self.baselineCompletionCount = try container.decodeBackendNonNegativeInt(forKey: .baselineCompletionCount)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        self.serverRevision = try container.decodeIfPresent(Int64.self, forKey: .serverRevision)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rewardId, forKey: .rewardId)
        try container.encode(recurringTaskId, forKey: .recurringTaskId)
        try container.encodeBackendPositiveInt(requiredCompletions, forKey: .requiredCompletions)
        try container.encodeBackendNonNegativeInt(baselineCompletionCount, forKey: .baselineCompletionCount)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    func toModel() -> RewardRecurringTaskDependency? {
        guard
            let createdAt = AppDateCoding.parseBackendTimestamp(createdAt),
            let updatedAt = AppDateCoding.parseBackendTimestamp(updatedAt)
        else {
            return nil
        }

        return RewardRecurringTaskDependency(
            rewardId: RecordID(rewardId),
            recurringTaskId: RecordID(recurringTaskId),
            requiredCompletions: requiredCompletions,
            baselineCompletionCount: baselineCompletionCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            serverRevision: serverRevision
        )
    }

    static func from(_ dependency: RewardRecurringTaskDependency) -> SyncRewardRecurringTaskDependencyRecord {
        SyncRewardRecurringTaskDependencyRecord(
            rewardId: dependency.rewardId.rawValue,
            recurringTaskId: dependency.recurringTaskId.rawValue,
            requiredCompletions: dependency.requiredCompletions,
            baselineCompletionCount: dependency.baselineCompletionCount,
            createdAt: AppDateCoding.backendTimestamp(from: dependency.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: dependency.updatedAt),
            deletedAt: dependency.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            serverRevision: dependency.serverRevision
        )
    }
}

struct SyncRewardTagRecord: Codable {
    let rewardId: String
    let tagId: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let serverRevision: Int64?

    init(
        rewardId: String,
        tagId: String,
        createdAt: String,
        updatedAt: String,
        deletedAt: String?,
        serverRevision: Int64? = nil
    ) {
        self.rewardId = rewardId
        self.tagId = tagId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverRevision = serverRevision
    }

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
            deletedAt: AppDateCoding.parseBackendTimestamp(deletedAt),
            serverRevision: serverRevision
        )
    }

    static func from(_ rewardTag: RewardTag) -> SyncRewardTagRecord {
        SyncRewardTagRecord(
            rewardId: rewardTag.rewardId.rawValue,
            tagId: rewardTag.tagId.rawValue,
            createdAt: AppDateCoding.backendTimestamp(from: rewardTag.createdAt),
            updatedAt: AppDateCoding.backendTimestamp(from: rewardTag.updatedAt),
            deletedAt: rewardTag.deletedAt.map { AppDateCoding.backendTimestamp(from: $0) },
            serverRevision: rewardTag.serverRevision
        )
    }
}

struct SyncOperation: Encodable {
    let operationId: UUID
    let kind: String
    let baseRecordRevision: Int64?
    let payload: SyncOperationPayload

    var taskPayload: SyncTaskRecord? {
        payload.taskPayload
    }

    var recurringTaskPayload: SyncRecurringTaskRecord? {
        payload.recurringTaskPayload
    }

    var timerPayload: SyncTimerRecord? {
        payload.timerPayload
    }

    var rewardPayload: SyncRewardRecord? {
        payload.rewardPayload
    }
}

enum SyncOperationPayload: Encodable {
    case timer(SyncTimerRecord)
    case task(SyncTaskRecord)
    case recurringTask(SyncRecurringTaskRecord)
    case trade(SyncTradeRecord)
    case tag(SyncTagRecord)
    case taskTag(SyncTaskTagRecord)
    case taskTaskDependency(SyncTaskTaskDependencyRecord)
    case taskRecurringTaskDependency(SyncTaskRecurringTaskDependencyRecord)
    case recurringTaskTag(SyncRecurringTaskTagRecord)
    case reward(SyncRewardRecord)
    case rewardTaskDependency(SyncRewardTaskDependencyRecord)
    case rewardRecurringTaskDependency(SyncRewardRecurringTaskDependencyRecord)
    case rewardTag(SyncRewardTagRecord)
    case themePalettes(SyncThemePalettes)

    var taskPayload: SyncTaskRecord? {
        if case .task(let payload) = self {
            return payload
        }
        return nil
    }

    var recurringTaskPayload: SyncRecurringTaskRecord? {
        if case .recurringTask(let payload) = self {
            return payload
        }
        return nil
    }

    var timerPayload: SyncTimerRecord? {
        if case .timer(let payload) = self {
            return payload
        }
        return nil
    }

    var rewardPayload: SyncRewardRecord? {
        if case .reward(let payload) = self {
            return payload
        }
        return nil
    }

    var themePalettesPayload: SyncThemePalettes? {
        if case .themePalettes(let payload) = self {
            return payload
        }
        return nil
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .timer(let payload):
            try payload.encode(to: encoder)
        case .task(let payload):
            try payload.encode(to: encoder)
        case .recurringTask(let payload):
            try payload.encode(to: encoder)
        case .trade(let payload):
            try payload.encode(to: encoder)
        case .tag(let payload):
            try payload.encode(to: encoder)
        case .taskTag(let payload):
            try payload.encode(to: encoder)
        case .taskTaskDependency(let payload):
            try payload.encode(to: encoder)
        case .taskRecurringTaskDependency(let payload):
            try payload.encode(to: encoder)
        case .recurringTaskTag(let payload):
            try payload.encode(to: encoder)
        case .reward(let payload):
            try payload.encode(to: encoder)
        case .rewardTaskDependency(let payload):
            try payload.encode(to: encoder)
        case .rewardRecurringTaskDependency(let payload):
            try payload.encode(to: encoder)
        case .rewardTag(let payload):
            try payload.encode(to: encoder)
        case .themePalettes(let payload):
            try payload.encode(to: encoder)
        }
    }
}

struct SyncPushRequest: Encodable {
    let baseCursor: String?
    let operations: [SyncOperation]

    init(
        baseCursor: String?,
        operations: [SyncOperation]
    ) {
        self.baseCursor = baseCursor
        self.operations = operations
    }
}
