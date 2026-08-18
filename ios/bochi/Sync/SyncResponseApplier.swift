import Foundation

// Sync flow: applies pull/push responses to local stores while preserving dirty
// rows and updating side projections like balance and theme palettes.
@MainActor
struct SyncResponseApplier {
    private let payloadPersistence: SyncPayloadPersistence
    private let balanceStore: BalanceStore
    private let userSettingsStore: UserSettingsStore

    init(
        payloadPersistence: SyncPayloadPersistence,
        balanceStore: BalanceStore,
        userSettingsStore: UserSettingsStore
    ) {
        self.payloadPersistence = payloadPersistence
        self.balanceStore = balanceStore
        self.userSettingsStore = userSettingsStore
    }

    func replaceCurrentOwnerStateFromFullPull(
        pullResponse: SyncResponse,
        localState: SyncLocalState,
        ownerID: String
    ) throws {
        let payload = try SyncPayloadMapper.makePayload(from: pullResponse)
        let authoritativePayload = SyncPayload(
            timers: OwnerScopedRecordSupport.applyingAuthoritativeRecords(
                local: payload.timers,
                remote: localState.dirtyTimers
            ),
            tasks: OwnerScopedRecordSupport.applyingAuthoritativeRecords(
                local: payload.tasks,
                remote: localState.dirtyTasks
            ),
            taskTaskDependencies: OwnerScopedRecordSupport.applyingAuthoritativeRecords(
                local: payload.taskTaskDependencies,
                remote: localState.dirtyTaskTaskDependencies
            ),
            taskRecurringTaskDependencies: OwnerScopedRecordSupport.applyingAuthoritativeRecords(
                local: payload.taskRecurringTaskDependencies,
                remote: localState.dirtyTaskRecurringTaskDependencies
            ),
            recurringTasks: OwnerScopedRecordSupport.applyingAuthoritativeRecords(
                local: payload.recurringTasks,
                remote: localState.dirtyRecurringTasks
            ),
            trades: OwnerScopedRecordSupport.applyingAuthoritativeRecords(
                local: payload.trades,
                remote: localState.dirtyTrades
            ),
            tags: OwnerScopedRecordSupport.applyingAuthoritativeRecords(
                local: payload.tags,
                remote: localState.dirtyTags
            ),
            taskTags: OwnerScopedRecordSupport.applyingAuthoritativeRecords(
                local: payload.taskTags,
                remote: localState.dirtyTaskTags + localState.localDraftTaskTags
            ),
            recurringTaskTags: OwnerScopedRecordSupport.applyingAuthoritativeRecords(
                local: payload.recurringTaskTags,
                remote: localState.dirtyRecurringTaskTags + localState.localDraftRecurringTaskTags
            ),
            rewards: OwnerScopedRecordSupport.applyingAuthoritativeRecords(
                local: payload.rewards,
                remote: localState.dirtyRewards
            ),
            rewardTaskDependencies: OwnerScopedRecordSupport.applyingAuthoritativeRecords(
                local: payload.rewardTaskDependencies,
                remote: localState.dirtyRewardTaskDependencies
            ),
            rewardRecurringTaskDependencies: OwnerScopedRecordSupport.applyingAuthoritativeRecords(
                local: payload.rewardRecurringTaskDependencies,
                remote: localState.dirtyRewardRecurringTaskDependencies
            ),
            rewardTags: OwnerScopedRecordSupport.applyingAuthoritativeRecords(
                local: payload.rewardTags,
                remote: localState.dirtyRewardTags + localState.localDraftRewardTags
            )
        )

        try payloadPersistence.persist(authoritativePayload, ownerID: ownerID)
        if !localState.dirtyTrades.isEmpty {
            balanceStore.refresh()
        } else {
            try balanceStore.persistBalance(pullResponse.balance.pointBalance)
        }
        if !localState.themePalettesDirty {
            try userSettingsStore.persistThemePalettes(pullResponse.themePalettes.toPreferences())
        }
    }

    func applyPullResponse(
        _ response: SyncResponse,
        filteringDirtyIDs dirtyIDs: SyncDirtyIDSnapshot,
        persistsThemePalettes: Bool,
        ownerID: String
    ) throws {
        let payload = try SyncPayloadMapper.makePayload(from: response, excluding: dirtyIDs)
        try payloadPersistence.persist(
            payloadPersistence.mergedCurrentPayload(with: payload),
            ownerID: ownerID
        )

        if dirtyIDs.trades.isEmpty {
            try balanceStore.persistBalance(response.balance.pointBalance)
        } else {
            balanceStore.refresh()
        }

        if persistsThemePalettes {
            try userSettingsStore.persistThemePalettes(response.themePalettes.toPreferences())
        }
    }

    func applyPushResponse(
        _ response: SyncResponse,
        filteringDirtyIDs dirtyIDs: SyncDirtyIDSnapshot,
        persistsThemePalettes: Bool,
        ownerID: String
    ) throws {
        try payloadPersistence.persist(
            payloadPersistence.mergedCurrentPayload(
                with: try SyncPayloadMapper.makePayload(from: response, excluding: dirtyIDs)
            ),
            ownerID: ownerID
        )
        try persistAcceptedPushServerRevisions(from: response, preservingDirtyIDs: dirtyIDs, ownerID: ownerID)

        if dirtyIDs.trades.isEmpty {
            try balanceStore.persistBalance(response.balance.pointBalance)
        } else {
            balanceStore.refresh()
        }

        if persistsThemePalettes {
            try userSettingsStore.persistThemePalettes(response.themePalettes.toPreferences())
        }
    }

    private func persistAcceptedPushServerRevisions(
        from response: SyncResponse,
        preservingDirtyIDs dirtyIDs: SyncDirtyIDSnapshot,
        ownerID: String
    ) throws {
        let timerRevisions = Dictionary(uniqueKeysWithValues: response.timers.compactMap { record -> (RecordID, Int64)? in
            let id = RecordID(record.id)
            guard dirtyIDs.timers[id] != nil, let serverRevision = record.serverRevision else { return nil }
            return (id, serverRevision)
        })
        let taskRevisions = Dictionary(uniqueKeysWithValues: response.tasks.compactMap { record -> (RecordID, Int64)? in
            let id = RecordID(record.id)
            guard dirtyIDs.tasks[id] != nil, let serverRevision = record.serverRevision else { return nil }
            return (id, serverRevision)
        })
        let taskTaskDependencyRevisions = Dictionary(uniqueKeysWithValues: response.taskTaskDependencies.compactMap { record -> (RecordID, Int64)? in
            let id = RecordID("\(record.taskId):\(record.dependsOnTaskId)")
            guard dirtyIDs.taskTaskDependencies[id] != nil, let serverRevision = record.serverRevision else { return nil }
            return (id, serverRevision)
        })
        let taskRecurringTaskDependencyRevisions = Dictionary(uniqueKeysWithValues: response.taskRecurringTaskDependencies.compactMap { record -> (RecordID, Int64)? in
            let id = RecordID("\(record.taskId):\(record.recurringTaskId)")
            guard dirtyIDs.taskRecurringTaskDependencies[id] != nil, let serverRevision = record.serverRevision else { return nil }
            return (id, serverRevision)
        })
        let recurringTaskRevisions = Dictionary(uniqueKeysWithValues: response.recurringTasks.compactMap { record -> (RecordID, Int64)? in
            let id = RecordID(record.id)
            guard dirtyIDs.recurringTasks[id] != nil, let serverRevision = record.serverRevision else { return nil }
            return (id, serverRevision)
        })
        let tradeRevisions = Dictionary(uniqueKeysWithValues: response.trades.compactMap { record -> (RecordID, Int64)? in
            let id = RecordID(record.id)
            guard dirtyIDs.trades[id] != nil, let serverRevision = record.serverRevision else { return nil }
            return (id, serverRevision)
        })
        let tagRevisions = Dictionary(uniqueKeysWithValues: response.tags.compactMap { record -> (RecordID, Int64)? in
            let id = RecordID(record.id)
            guard dirtyIDs.tags[id] != nil, let serverRevision = record.serverRevision else { return nil }
            return (id, serverRevision)
        })
        let taskTagRevisions = Dictionary(uniqueKeysWithValues: response.taskTags.compactMap { record -> (RecordID, Int64)? in
            let id = RecordID("\(record.taskId):\(record.tagId)")
            guard dirtyIDs.taskTags[id] != nil, let serverRevision = record.serverRevision else { return nil }
            return (id, serverRevision)
        })
        let recurringTaskTagRevisions = Dictionary(uniqueKeysWithValues: response.recurringTaskTags.compactMap { record -> (RecordID, Int64)? in
            let id = RecordID("\(record.recurringTaskId):\(record.tagId)")
            guard dirtyIDs.recurringTaskTags[id] != nil, let serverRevision = record.serverRevision else { return nil }
            return (id, serverRevision)
        })
        let rewardRevisions = Dictionary(uniqueKeysWithValues: response.rewards.compactMap { record -> (RecordID, Int64)? in
            let id = RecordID(record.id)
            guard dirtyIDs.rewards[id] != nil, let serverRevision = record.serverRevision else { return nil }
            return (id, serverRevision)
        })
        let rewardTaskDependencyRevisions = Dictionary(uniqueKeysWithValues: response.rewardTaskDependencies.compactMap { record -> (RecordID, Int64)? in
            let id = RecordID("\(record.rewardId):\(record.dependsOnTaskId)")
            guard dirtyIDs.rewardTaskDependencies[id] != nil, let serverRevision = record.serverRevision else { return nil }
            return (id, serverRevision)
        })
        let rewardRecurringTaskDependencyRevisions = Dictionary(uniqueKeysWithValues: response.rewardRecurringTaskDependencies.compactMap { record -> (RecordID, Int64)? in
            let id = RecordID("\(record.rewardId):\(record.recurringTaskId)")
            guard dirtyIDs.rewardRecurringTaskDependencies[id] != nil, let serverRevision = record.serverRevision else { return nil }
            return (id, serverRevision)
        })
        let rewardTagRevisions = Dictionary(uniqueKeysWithValues: response.rewardTags.compactMap { record -> (RecordID, Int64)? in
            let id = RecordID("\(record.rewardId):\(record.tagId)")
            guard dirtyIDs.rewardTags[id] != nil, let serverRevision = record.serverRevision else { return nil }
            return (id, serverRevision)
        })

        guard !timerRevisions.isEmpty
            || !taskRevisions.isEmpty
            || !taskTaskDependencyRevisions.isEmpty
            || !taskRecurringTaskDependencyRevisions.isEmpty
            || !recurringTaskRevisions.isEmpty
            || !tradeRevisions.isEmpty
            || !tagRevisions.isEmpty
            || !taskTagRevisions.isEmpty
            || !recurringTaskTagRevisions.isEmpty
            || !rewardRevisions.isEmpty
            || !rewardTaskDependencyRevisions.isEmpty
            || !rewardRecurringTaskDependencyRevisions.isEmpty
            || !rewardTagRevisions.isEmpty else {
            return
        }

        let currentPayload = payloadPersistence.currentPayload()
        let payload = SyncPayload(
            timers: currentPayload.timers.map { timer in timer.withServerRevision(timerRevisions[timer.id]) },
            tasks: currentPayload.tasks.map { task in task.withServerRevision(taskRevisions[task.id]) },
            taskTaskDependencies: currentPayload.taskTaskDependencies.map { dependency in
                dependency.withServerRevision(taskTaskDependencyRevisions[dependency.id])
            },
            taskRecurringTaskDependencies: currentPayload.taskRecurringTaskDependencies.map { dependency in
                dependency.withServerRevision(taskRecurringTaskDependencyRevisions[dependency.id])
            },
            recurringTasks: currentPayload.recurringTasks.map { recurringTask in
                recurringTask.withServerRevision(recurringTaskRevisions[recurringTask.id])
            },
            trades: currentPayload.trades.map { trade in trade.withServerRevision(tradeRevisions[trade.id]) },
            tags: currentPayload.tags.map { tag in tag.withServerRevision(tagRevisions[tag.id]) },
            taskTags: currentPayload.taskTags.map { tag in tag.withServerRevision(taskTagRevisions[tag.id]) },
            recurringTaskTags: currentPayload.recurringTaskTags.map { tag in
                tag.withServerRevision(recurringTaskTagRevisions[tag.id])
            },
            rewards: currentPayload.rewards.map { reward in reward.withServerRevision(rewardRevisions[reward.id]) },
            rewardTaskDependencies: currentPayload.rewardTaskDependencies.map { dependency in
                dependency.withServerRevision(rewardTaskDependencyRevisions[dependency.id])
            },
            rewardRecurringTaskDependencies: currentPayload.rewardRecurringTaskDependencies.map { dependency in
                dependency.withServerRevision(rewardRecurringTaskDependencyRevisions[dependency.id])
            },
            rewardTags: currentPayload.rewardTags.map { tag in tag.withServerRevision(rewardTagRevisions[tag.id]) }
        )
        try payloadPersistence.persist(payload, ownerID: ownerID)
    }
}

private extension BochiTimer {
    func withServerRevision(_ serverRevision: Int64?) -> BochiTimer {
        guard let serverRevision else { return self }
        return BochiTimer(
            id: id,
            name: name,
            intervals: intervals,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            serverRevision: serverRevision
        )
    }
}

private extension TaskItem {
    func withServerRevision(_ serverRevision: Int64?) -> TaskItem {
        guard let serverRevision else { return self }
        return TaskItem(
            id: id,
            name: name,
            description: description,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            basePrice: basePrice,
            dueDate: dueDate,
            pinned: pinned,
            hidden: hidden,
            timerSelection: timerSelection,
            serverRevision: serverRevision
        )
    }
}

private extension RecurringTask {
    func withServerRevision(_ serverRevision: Int64?) -> RecurringTask {
        guard let serverRevision else { return self }
        return RecurringTask(
            id: id,
            name: name,
            description: description,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            frequency: frequency,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: basePrice,
            pinned: pinned,
            hidden: hidden,
            timerSelection: timerSelection,
            serverRevision: serverRevision
        )
    }
}

private extension Trade {
    func withServerRevision(_ serverRevision: Int64?) -> Trade {
        guard let serverRevision else { return self }
        return Trade(
            id: id,
            taskId: taskId,
            recurringTaskId: recurringTaskId,
            rewardId: rewardId,
            sourceName: sourceName,
            amount: amount,
            vaultAmountMicro: vaultAmountMicro,
            adjustmentBaseAmount: adjustmentBaseAmount,
            oneTimeAdjustmentMultiplier: oneTimeAdjustmentMultiplier,
            tradeKind: tradeKind,
            vaultInterestHour: vaultInterestHour,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            refundsTradeId: refundsTradeId,
            serverRevision: serverRevision
        )
    }
}

private extension Tag {
    func withServerRevision(_ serverRevision: Int64?) -> Tag {
        guard let serverRevision else { return self }
        return Tag(
            id: id,
            name: name,
            colorHex: colorHex,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            serverRevision: serverRevision
        )
    }
}

private extension TaskTag {
    func withServerRevision(_ serverRevision: Int64?) -> TaskTag {
        guard let serverRevision else { return self }
        return TaskTag(
            taskId: taskId,
            tagId: tagId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            serverRevision: serverRevision
        )
    }
}

private extension RecurringTaskTag {
    func withServerRevision(_ serverRevision: Int64?) -> RecurringTaskTag {
        guard let serverRevision else { return self }
        return RecurringTaskTag(
            recurringTaskId: recurringTaskId,
            tagId: tagId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            serverRevision: serverRevision
        )
    }
}

private extension RewardTag {
    func withServerRevision(_ serverRevision: Int64?) -> RewardTag {
        guard let serverRevision else { return self }
        return RewardTag(
            rewardId: rewardId,
            tagId: tagId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            serverRevision: serverRevision
        )
    }
}

private extension TaskTaskDependency {
    func withServerRevision(_ serverRevision: Int64?) -> TaskTaskDependency {
        guard let serverRevision else { return self }
        return TaskTaskDependency(
            taskId: taskId,
            dependsOnTaskId: dependsOnTaskId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            serverRevision: serverRevision
        )
    }
}

private extension TaskRecurringTaskDependency {
    func withServerRevision(_ serverRevision: Int64?) -> TaskRecurringTaskDependency {
        guard let serverRevision else { return self }
        return TaskRecurringTaskDependency(
            taskId: taskId,
            recurringTaskId: recurringTaskId,
            requiredCompletions: requiredCompletions,
            baselineCompletionCount: baselineCompletionCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            serverRevision: serverRevision
        )
    }
}

private extension Reward {
    func withServerRevision(_ serverRevision: Int64?) -> Reward {
        guard let serverRevision else { return self }
        return Reward(
            id: id,
            recurring: recurring,
            name: name,
            description: description,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            maxFrequency: maxFrequency,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: basePrice,
            pinned: pinned,
            hidden: hidden,
            timerSelection: timerSelection,
            serverRevision: serverRevision
        )
    }
}

private extension RewardTaskDependency {
    func withServerRevision(_ serverRevision: Int64?) -> RewardTaskDependency {
        guard let serverRevision else { return self }
        return RewardTaskDependency(
            rewardId: rewardId,
            dependsOnTaskId: dependsOnTaskId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            serverRevision: serverRevision
        )
    }
}

private extension RewardRecurringTaskDependency {
    func withServerRevision(_ serverRevision: Int64?) -> RewardRecurringTaskDependency {
        guard let serverRevision else { return self }
        return RewardRecurringTaskDependency(
            rewardId: rewardId,
            recurringTaskId: recurringTaskId,
            requiredCompletions: requiredCompletions,
            baselineCompletionCount: baselineCompletionCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            serverRevision: serverRevision
        )
    }
}
