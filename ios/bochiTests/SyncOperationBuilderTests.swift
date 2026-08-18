import Foundation
import Testing
@testable import bochi

@MainActor
struct SyncOperationBuilderTests {
    // Behaviour: retrying the same local edit should reuse the same operation
    // ID, while a later edit to the same row should get a fresh operation ID.
    @Test("Dirty generation determines stable operation IDs")
    func dirtyGenerationDeterminesStableOperationIDs() throws {
        let taskID = RecordID("task-1")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = TaskItem(
            id: taskID,
            name: "Plan the week",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            basePrice: 420,
            dueDate: nil,
            serverRevision: 7
        )
        var dirtySnapshot = SyncDirtyIDSnapshot()
        dirtySnapshot.tasks[taskID] = 42

        let operations = SyncOperationBuilder.makeUpsertOperations(
            timers: [],
            tasks: [task],
            taskTaskDependencies: [],
            taskRecurringTaskDependencies: [],
            recurringTasks: [],
            trades: [],
            tags: [],
            taskTags: [],
            recurringTaskTags: [],
            rewards: [],
            rewardTaskDependencies: [],
            rewardRecurringTaskDependencies: [],
            rewardTags: [],
            dirtySnapshot: dirtySnapshot
        )

        let operation = try #require(operations.first)
        let taskPayload = try #require(operation.taskPayload)
        #expect(operations.count == 1)
        #expect(operation.kind == "upsertTask")
        #expect(operation.baseRecordRevision == 7)
        #expect(operation.operationId == SyncOperationBuilder.operationID(
            entityKind: "task",
            recordID: taskID,
            generation: 42
        ))
        #expect(operation.operationId != SyncOperationBuilder.operationID(
            entityKind: "task",
            recordID: taskID,
            generation: 43
        ))
        #expect(taskPayload.id == taskID.rawValue)
        #expect(taskPayload.basePrice == 420)
    }

    // Behaviour: revision zero is a real server base revision, not a missing
    // revision, so every synced row type must send it when edited locally.
    @Test("Revision zero is sent as a base revision")
    func revisionZeroIsSentAsBaseRevision() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timerID = RecordID("timer-1")
        let taskID = RecordID("task-1")
        let dependencyTaskID = RecordID("task-2")
        let recurringTaskID = RecordID("recurring-task-1")
        let tradeID = RecordID("trade-1")
        let tagID = RecordID("tag-1")
        let rewardID = RecordID("reward-1")

        let timer = BochiTimer(
            id: timerID,
            name: "Work block",
            intervals: [TimerInterval(name: "Focus", durationSeconds: 300)],
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            serverRevision: 0
        )
        let task = TaskItem(
            id: taskID,
            name: "Plan",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            basePrice: 100,
            dueDate: nil,
            serverRevision: 0
        )
        let taskTaskDependency = TaskTaskDependency(
            taskId: taskID,
            dependsOnTaskId: dependencyTaskID,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            serverRevision: 0
        )
        let taskRecurringTaskDependency = TaskRecurringTaskDependency(
            taskId: taskID,
            recurringTaskId: recurringTaskID,
            requiredCompletions: 1,
            baselineCompletionCount: 0,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            serverRevision: 0
        )
        let recurringTask = RecurringTask(
            id: recurringTaskID,
            name: "Walk",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            frequency: 1,
            lockoutDurationSeconds: nil,
            basePrice: 100,
            serverRevision: 0
        )
        let trade = Trade(
            id: tradeID,
            taskId: taskID,
            recurringTaskId: nil,
            rewardId: nil,
            amount: 100,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            serverRevision: 0
        )
        let tag = Tag(
            id: tagID,
            name: "Focus",
            colorHex: "#111111",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            serverRevision: 0
        )
        let taskTag = TaskTag(
            taskId: taskID,
            tagId: tagID,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            serverRevision: 0
        )
        let recurringTaskTag = RecurringTaskTag(
            recurringTaskId: recurringTaskID,
            tagId: tagID,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            serverRevision: 0
        )
        let reward = Reward(
            id: rewardID,
            recurring: true,
            name: "Coffee",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            maxFrequency: nil,
            lockoutDurationSeconds: nil,
            basePrice: 500,
            serverRevision: 0
        )
        let rewardTaskDependency = RewardTaskDependency(
            rewardId: rewardID,
            dependsOnTaskId: taskID,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            serverRevision: 0
        )
        let rewardRecurringTaskDependency = RewardRecurringTaskDependency(
            rewardId: rewardID,
            recurringTaskId: recurringTaskID,
            requiredCompletions: 1,
            baselineCompletionCount: 0,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            serverRevision: 0
        )
        let rewardTag = RewardTag(
            rewardId: rewardID,
            tagId: tagID,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            serverRevision: 0
        )
        var dirtySnapshot = SyncDirtyIDSnapshot()
        dirtySnapshot.timers[timerID] = 1
        dirtySnapshot.tasks[taskID] = 1
        dirtySnapshot.taskTaskDependencies[taskTaskDependency.id] = 1
        dirtySnapshot.taskRecurringTaskDependencies[taskRecurringTaskDependency.id] = 1
        dirtySnapshot.recurringTasks[recurringTaskID] = 1
        dirtySnapshot.trades[tradeID] = 1
        dirtySnapshot.tags[tagID] = 1
        dirtySnapshot.taskTags[taskTag.id] = 1
        dirtySnapshot.recurringTaskTags[recurringTaskTag.id] = 1
        dirtySnapshot.rewards[rewardID] = 1
        dirtySnapshot.rewardTaskDependencies[rewardTaskDependency.id] = 1
        dirtySnapshot.rewardRecurringTaskDependencies[rewardRecurringTaskDependency.id] = 1
        dirtySnapshot.rewardTags[rewardTag.id] = 1

        let operations = SyncOperationBuilder.makeUpsertOperations(
            timers: [timer],
            tasks: [task],
            taskTaskDependencies: [taskTaskDependency],
            taskRecurringTaskDependencies: [taskRecurringTaskDependency],
            recurringTasks: [recurringTask],
            trades: [trade],
            tags: [tag],
            taskTags: [taskTag],
            recurringTaskTags: [recurringTaskTag],
            rewards: [reward],
            rewardTaskDependencies: [rewardTaskDependency],
            rewardRecurringTaskDependencies: [rewardRecurringTaskDependency],
            rewardTags: [rewardTag],
            dirtySnapshot: dirtySnapshot
        )

        #expect(operations.count == 13)
        #expect(operations.allSatisfy { $0.baseRecordRevision == 0 })
    }

    // Behaviour: theme changes sync through the same deterministic operation
    // envelope as row edits, but without a row-level server revision.
    @Test("Theme palette operation uses theme generation")
    func themePaletteOperationUsesThemeGeneration() throws {
        let palettes = SyncThemePalettes(
            main: .mint,
            accent: .palette(.jade)
        )

        let operation = SyncOperationBuilder.makeThemePalettesOperation(
            themePalettes: palettes,
            generation: 9
        )

        let payload = try #require(operation.payload.themePalettesPayload)
        #expect(operation.kind == "updateThemePalettes")
        #expect(operation.baseRecordRevision == nil)
        #expect(operation.operationId == SyncOperationBuilder.operationID(
            entityKind: "themePalettes",
            recordID: RecordID("themePalettes"),
            generation: 9
        ))
        #expect(payload == palettes)
    }

    // Behaviour: if a user edits a row while a push response is in flight, that
    // newer dirty generation must survive the response and retry later.
    @Test("Dirty snapshot keeps only post-snapshot edits")
    func dirtySnapshotKeepsOnlyPostSnapshotEdits() {
        let unchangedTaskID = RecordID("unchanged-task")
        let editedTaskID = RecordID("edited-task")
        let newTaskID = RecordID("new-task")
        var snapshot = SyncStateStore.UserSyncState()
        snapshot.dirty.tasks = [
            SyncStateStore.DirtyRecordVersion(id: unchangedTaskID, generation: 1),
            SyncStateStore.DirtyRecordVersion(id: editedTaskID, generation: 2)
        ]
        var current = SyncStateStore.UserSyncState()
        current.dirty.tasks = [
            SyncStateStore.DirtyRecordVersion(id: unchangedTaskID, generation: 1),
            SyncStateStore.DirtyRecordVersion(id: editedTaskID, generation: 3),
            SyncStateStore.DirtyRecordVersion(id: newTaskID, generation: 4)
        ]

        let changes = SyncDirtyIDSnapshot.changes(after: current, snapshot: snapshot)

        #expect(changes.tasks == [
            editedTaskID: 3,
            newTaskID: 4
        ])
    }
}
