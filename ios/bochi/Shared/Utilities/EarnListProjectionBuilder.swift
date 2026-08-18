import Foundation

enum EarnListRowID: Hashable, Sendable {
    case task(RecordID)
    case recurringTask(RecordID)
}

struct EarnTaskRowModel: Sendable {
    let task: TaskItem
    let tags: [Tag]
    let price: Int
    let canComplete: Bool
    let isCompleted: Bool
    let isBlocked: Bool
}

struct EarnRecurringTaskRowModel: Sendable {
    let recurringTask: RecurringTask
    let tags: [Tag]
    let isLocked: Bool
    let price: Int
    let quote: RecurringTaskTradeQuote
}

enum EarnListRowModel: Identifiable, Sendable {
    case task(EarnTaskRowModel)
    case recurringTask(EarnRecurringTaskRowModel)

    nonisolated var id: EarnListRowID {
        switch self {
        case .task(let row):
            return .task(row.task.id)
        case .recurringTask(let row):
            return .recurringTask(row.recurringTask.id)
        }
    }
}

struct EarnListProjection: Sendable {
    var activeTasks: [TaskItem] = []
    var activeRecurringTasks: [RecurringTask] = []
    var visibleRows: [EarnListRowModel] = []

    var rowIDs: [EarnListRowID] {
        visibleRows.map(\.id)
    }
}

struct EarnListProjectionInputs: Sendable {
    let tasks: [TaskItem]
    let recurringTasks: [RecurringTask]
    let taskTagsByID: [RecordID: [Tag]]
    let recurringTaskTagsByID: [RecordID: [Tag]]
    let activeTagIDs: Set<RecordID>
    let taskTaskDependencies: [TaskTaskDependency]
    let taskRecurringTaskDependencies: [TaskRecurringTaskDependency]
    let latestTaskTradesByTaskID: [RecordID: Trade]
    let recurringTaskCompletionCountsByRecurringTaskID: [RecordID: Int]
    let recurringTaskTradeDatesByRecurringTaskID: [RecordID: [Date]]
    let preferences: EntityListPreferences
    let hasPremiumAccess: Bool
    let now: Date
}

nonisolated enum EarnListProjectionBuilder {
    static func makeProjection(inputs: EarnListProjectionInputs) -> EarnListProjection {
        let activeTasks = inputs.tasks.filter { $0.deletedAt == nil }
        let activeRecurringTasks = inputs.recurringTasks.filter { $0.deletedAt == nil }
        let rows = taskRows(tasks: activeTasks, inputs: inputs).map(EarnListRowModel.task)
            + recurringTaskRows(recurringTasks: activeRecurringTasks, inputs: inputs).map(EarnListRowModel.recurringTask)

        return EarnListProjection(
            activeTasks: activeTasks,
            activeRecurringTasks: activeRecurringTasks,
            visibleRows: orderedRows(visibleRows(rows, inputs: inputs))
        )
    }

    private static func taskRows(
        tasks: [TaskItem],
        inputs: EarnListProjectionInputs
    ) -> [EarnTaskRowModel] {
        let blockedTaskIDs = EntityDependencyBlockingSupport.blockedTaskIDs(
            tasks: tasks,
            allTasks: inputs.tasks,
            taskTaskDependencies: inputs.taskTaskDependencies,
            taskRecurringTaskDependencies: inputs.taskRecurringTaskDependencies,
            latestTaskTradesByTaskID: inputs.latestTaskTradesByTaskID,
            recurringTaskCompletionCountsByRecurringTaskID: inputs.recurringTaskCompletionCountsByRecurringTaskID,
            hasPremiumAccess: inputs.hasPremiumAccess
        )
        let completedTaskIDs = Set(inputs.latestTaskTradesByTaskID.keys)

        return tasks.map { task in
            EarnTaskRowModel(
                task: task,
                tags: inputs.taskTagsByID[task.id, default: []],
                price: TaskPriceCalculator.calculatePrice(task: task),
                canComplete: task.canTrade && !completedTaskIDs.contains(task.id),
                isCompleted: completedTaskIDs.contains(task.id),
                isBlocked: blockedTaskIDs.contains(task.id)
            )
        }
    }

    private static func recurringTaskRows(
        recurringTasks: [RecurringTask],
        inputs: EarnListProjectionInputs
    ) -> [EarnRecurringTaskRowModel] {
        recurringTasks.map { recurringTask in
            let completionDates = inputs.recurringTaskTradeDatesByRecurringTaskID[recurringTask.id, default: []]
            let isLocked = RecurringTaskLockout.remainingSeconds(
                recurringTask: recurringTask,
                completionDates: completionDates,
                now: inputs.now,
                hasPremiumAccess: inputs.hasPremiumAccess
            ) != nil
            let quote = RecurringTaskTradeQuote(completionDates: completionDates, pricedAt: inputs.now)
            let price = quote.totalPrice(
                recurringTask: recurringTask,
                allRecurringTasks: recurringTasks,
                quantity: 1
            )

            return EarnRecurringTaskRowModel(
                recurringTask: recurringTask,
                tags: inputs.recurringTaskTagsByID[recurringTask.id, default: []],
                isLocked: isLocked,
                price: price,
                quote: quote
            )
        }
    }

    private static func visibleRows(
        _ rows: [EarnListRowModel],
        inputs: EarnListProjectionInputs
    ) -> [EarnListRowModel] {
        EntityListQuery.apply(
            items: rows,
            preferences: inputs.preferences,
            hasPremiumAccess: inputs.hasPremiumAccess,
            validTagIDs: inputs.activeTagIDs,
            id: \.recordID,
            createdAt: \.createdAt,
            price: \.sortablePrice,
            tags: \.tags,
            statuses: \.statuses,
            isPinned: \.isPinned,
            isDeprioritized: { row in
                if case .task(let taskRow) = row {
                    return taskRow.task.canTrade && taskRow.isBlocked
                }
                return false
            }
        )
    }

    private static func orderedRows(_ rows: [EarnListRowModel]) -> [EarnListRowModel] {
        [
            (isLocked: false, isHidden: false),
            (isLocked: true, isHidden: false),
            (isLocked: false, isHidden: true),
            (isLocked: true, isHidden: true)
        ].flatMap { group in
            rows.filter { row in
                row.isLocked == group.isLocked && row.isHidden == group.isHidden
            }
        }
    }
}

extension EarnListRowModel {
    nonisolated var recordID: RecordID {
        switch self {
        case .task(let row):
            return row.task.id
        case .recurringTask(let row):
            return row.recurringTask.id
        }
    }

    nonisolated var createdAt: Date {
        switch self {
        case .task(let row):
            return row.task.createdAt
        case .recurringTask(let row):
            return row.recurringTask.createdAt
        }
    }

    nonisolated var sortablePrice: Int? {
        switch self {
        case .task(let row):
            return EntityActionSupport.sortableAmount(isActionable: row.canComplete) {
                row.price
            }
        case .recurringTask(let row):
            return EntityActionSupport.sortableAmount(isActionable: row.recurringTask.canTrade && !row.isLocked) {
                row.price
            }
        }
    }

    nonisolated var tags: [Tag] {
        switch self {
        case .task(let row):
            return row.tags
        case .recurringTask(let row):
            return row.tags
        }
    }

    nonisolated var statuses: Set<EntityListStatusFilter> {
        switch self {
        case .task(let taskRow):
            var statuses: Set<EntityListStatusFilter> = [.task, taskRow.isCompleted ? .completed : .incomplete]
            if taskRow.task.hidden {
                statuses.insert(.hidden)
            }
            if taskRow.isBlocked {
                statuses.insert(.locked)
            }
            return statuses
        case .recurringTask(let recurringTaskRow):
            var statuses: Set<EntityListStatusFilter> = [.recurringTask]
            if recurringTaskRow.recurringTask.hidden {
                statuses.insert(.hidden)
            }
            if recurringTaskRow.isLocked {
                statuses.insert(.locked)
            }
            return statuses
        }
    }

    nonisolated var isPinned: Bool {
        switch self {
        case .task(let row):
            return row.task.pinned
        case .recurringTask(let row):
            return row.recurringTask.pinned
        }
    }

    nonisolated var isHidden: Bool {
        switch self {
        case .task(let row):
            return row.task.hidden
        case .recurringTask(let row):
            return row.recurringTask.hidden
        }
    }

    nonisolated var isLocked: Bool {
        switch self {
        case .task(let row):
            return row.isBlocked
        case .recurringTask(let row):
            return row.isLocked
        }
    }

    nonisolated var themeRole: BochiThemeRole {
        switch self {
        case .task:
            return .task
        case .recurringTask:
            return .recurringTask
        }
    }
}

extension EarnTaskRowModel {
    nonisolated var listStatus: EntityListRowStatus? {
        if isBlocked {
            return .locked
        }
        if task.hidden {
            return .hidden
        }
        if isCompleted {
            return .completed
        }
        return nil
    }
}

extension EarnRecurringTaskRowModel {
    nonisolated var listStatus: EntityListRowStatus? {
        if isLocked {
            return .locked
        }
        if recurringTask.hidden {
            return .hidden
        }
        return nil
    }
}
