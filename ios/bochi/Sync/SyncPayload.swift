import Foundation

// Sync flow: grouped owner records used when mapping server responses, merging
// with local state, and persisting an authoritative snapshot.
struct SyncPayload {
    let timers: [BochiTimer]
    let tasks: [TaskItem]
    let taskTaskDependencies: [TaskTaskDependency]
    let taskRecurringTaskDependencies: [TaskRecurringTaskDependency]
    let recurringTasks: [RecurringTask]
    let trades: [Trade]
    let tags: [Tag]
    let taskTags: [TaskTag]
    let recurringTaskTags: [RecurringTaskTag]
    let rewards: [Reward]
    let rewardTaskDependencies: [RewardTaskDependency]
    let rewardRecurringTaskDependencies: [RewardRecurringTaskDependency]
    let rewardTags: [RewardTag]
}

enum SyncPayloadMappingError: LocalizedError {
    case malformedRecord(kind: String, id: String)

    var errorDescription: String? {
        switch self {
        case let .malformedRecord(kind, id):
            return "Sync failed because the server returned a malformed \(kind) record (\(id))."
        }
    }
}

enum SyncPayloadMapper {
    static func makePayload(
        from response: SyncResponse,
        excluding dirtyIDs: SyncDirtyIDSnapshot? = nil
    ) throws -> SyncPayload {
        SyncPayload(
            timers: try response.timers.compactMap { record in
                guard let model = record.toModel() else {
                    throw SyncPayloadMappingError.malformedRecord(kind: "timer", id: record.id)
                }
                guard dirtyIDs?.timers[model.id] == nil else { return nil }
                return model
            },
            tasks: try response.tasks.compactMap { record in
                guard let model = record.toModel() else {
                    throw SyncPayloadMappingError.malformedRecord(kind: "task", id: record.id)
                }
                guard dirtyIDs?.tasks[model.id] == nil else { return nil }
                return model
            },
            taskTaskDependencies: try response.taskTaskDependencies.compactMap { record in
                guard let model = record.toModel() else {
                    throw SyncPayloadMappingError.malformedRecord(
                        kind: "task-task dependency",
                        id: "\(record.taskId):\(record.dependsOnTaskId)"
                    )
                }
                guard dirtyIDs?.taskTaskDependencies[model.id] == nil else { return nil }
                return model
            },
            taskRecurringTaskDependencies: try response.taskRecurringTaskDependencies.compactMap { record in
                guard let model = record.toModel() else {
                    throw SyncPayloadMappingError.malformedRecord(
                        kind: "task-recurring task dependency",
                        id: "\(record.taskId):\(record.recurringTaskId)"
                    )
                }
                guard dirtyIDs?.taskRecurringTaskDependencies[model.id] == nil else { return nil }
                return model
            },
            recurringTasks: try response.recurringTasks.compactMap { record in
                guard let model = record.toModel() else {
                    throw SyncPayloadMappingError.malformedRecord(kind: "recurring task", id: record.id)
                }
                guard dirtyIDs?.recurringTasks[model.id] == nil else { return nil }
                return model
            },
            trades: try response.trades.compactMap { record in
                guard let model = record.toModel() else {
                    throw SyncPayloadMappingError.malformedRecord(kind: "trade", id: record.id)
                }
                guard dirtyIDs?.trades[model.id] == nil else { return nil }
                return model
            },
            tags: try response.tags.compactMap { record in
                guard let model = record.toModel() else {
                    throw SyncPayloadMappingError.malformedRecord(kind: "tag", id: record.id)
                }
                guard dirtyIDs?.tags[model.id] == nil else { return nil }
                return model
            },
            taskTags: try response.taskTags.compactMap { record in
                guard let model = record.toModel() else {
                    throw SyncPayloadMappingError.malformedRecord(kind: "task tag", id: "\(record.taskId):\(record.tagId)")
                }
                guard dirtyIDs?.taskTags[model.id] == nil else { return nil }
                return model
            },
            recurringTaskTags: try response.recurringTaskTags.compactMap { record in
                guard let model = record.toModel() else {
                    throw SyncPayloadMappingError.malformedRecord(
                        kind: "recurring task tag",
                        id: "\(record.recurringTaskId):\(record.tagId)"
                    )
                }
                guard dirtyIDs?.recurringTaskTags[model.id] == nil else { return nil }
                return model
            },
            rewards: try response.rewards.compactMap { record in
                guard let model = record.toModel() else {
                    throw SyncPayloadMappingError.malformedRecord(kind: "reward", id: record.id)
                }
                guard dirtyIDs?.rewards[model.id] == nil else { return nil }
                return model
            },
            rewardTaskDependencies: try response.rewardTaskDependencies.compactMap { record in
                guard let model = record.toModel() else {
                    throw SyncPayloadMappingError.malformedRecord(
                        kind: "reward-task dependency",
                        id: "\(record.rewardId):\(record.dependsOnTaskId)"
                    )
                }
                guard dirtyIDs?.rewardTaskDependencies[model.id] == nil else { return nil }
                return model
            },
            rewardRecurringTaskDependencies: try response.rewardRecurringTaskDependencies.compactMap { record in
                guard let model = record.toModel() else {
                    throw SyncPayloadMappingError.malformedRecord(
                        kind: "reward-recurring task dependency",
                        id: "\(record.rewardId):\(record.recurringTaskId)"
                    )
                }
                guard dirtyIDs?.rewardRecurringTaskDependencies[model.id] == nil else { return nil }
                return model
            },
            rewardTags: try response.rewardTags.compactMap { record in
                guard let model = record.toModel() else {
                    throw SyncPayloadMappingError.malformedRecord(kind: "reward tag", id: "\(record.rewardId):\(record.tagId)")
                }
                guard dirtyIDs?.rewardTags[model.id] == nil else { return nil }
                return model
            }
        )
    }
}
