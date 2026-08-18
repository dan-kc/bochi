import Foundation
import Testing
@testable import bochi

@MainActor
struct SyncLocalStateCollectorTests {
    private let ownerID = "user-123"

    @MainActor
    private struct TestContext {
        let syncStateStore: SyncStateStore
        let taskStore: TaskStore
        let taskDependencyStore: TaskDependencyStore
        let rewardDependencyStore: RewardDependencyStore
        let recurringTaskStore: RecurringTaskStore
        let rewardStore: RewardStore
        let tradeStore: TradeStore
        let tagStore: TagStore
        let timerStore: TimerStore

        var collector: SyncLocalStateCollector {
            SyncLocalStateCollector(
                timerStore: timerStore,
                taskStore: taskStore,
                taskDependencyStore: taskDependencyStore,
                rewardDependencyStore: rewardDependencyStore,
                recurringTaskStore: recurringTaskStore,
                rewardStore: rewardStore,
                tradeStore: tradeStore,
                tagStore: tagStore
            )
        }

        func collect(ownerID: String) -> SyncLocalState {
            collector.collect(from: syncStateStore.state(for: ownerID))
        }
    }

    private func makeContext() -> TestContext {
        let storageURL = TestHelpers.makeTemporaryFileURL("sync-local-state-collector")
        let timerStore = TimerStore(storageURL: storageURL)
        timerStore.setCurrentOwner(ownerID)
        return TestContext(
            syncStateStore: SyncStateStore(storageURL: storageURL),
            taskStore: TaskStore(storageURL: storageURL, initialOwnerID: ownerID),
            taskDependencyStore: TaskDependencyStore(storageURL: storageURL, initialOwnerID: ownerID),
            rewardDependencyStore: RewardDependencyStore(storageURL: storageURL, initialOwnerID: ownerID),
            recurringTaskStore: RecurringTaskStore(storageURL: storageURL, initialOwnerID: ownerID),
            rewardStore: RewardStore(storageURL: storageURL, initialOwnerID: ownerID),
            tradeStore: TradeStore(storageURL: storageURL, initialOwnerID: ownerID),
            tagStore: TagStore(storageURL: storageURL, initialOwnerID: ownerID),
            timerStore: timerStore
        )
    }

    // Behaviour: a dirty tag assignment whose task no longer exists should not
    // push to the backend, and should be reported for local cleanup after sync.
    @Test("Invalid dirty task tag is excluded from push state")
    func invalidDirtyTaskTagIsExcludedFromPushState() throws {
        let context = makeContext()
        let missingTaskID = RecordID("missing-task")
        let tag = try #require(context.tagStore.addTag(id: "tag-1", name: "Home"))

        context.tagStore.addTagToTask(tagId: tag.id, taskId: missingTaskID)

        let localState = context.collect(ownerID: ownerID)

        #expect(localState.dirtyTaskTags.isEmpty)
        #expect(localState.invalidDirtyTaskTagIDs == [RecordID("\(missingTaskID):\(tag.id)")])
        #expect(localState.dirtyTags.map(\.id) == [tag.id])
    }

    // Behaviour: full sync replacement should keep local draft tag links that
    // are waiting for their new unsynced entity, even when the link itself is
    // not dirty yet.
    @Test("Non-dirty draft task tags are preserved for full sync")
    func nonDirtyDraftTaskTagsArePreservedForFullSync() throws {
        let context = makeContext()
        let draftTaskID = RecordID("draft-task")
        let tag = try #require(context.tagStore.addTag(id: "tag-1", name: "Home", shouldNotifySync: false))

        context.tagStore.addTagToTask(tagId: tag.id, taskId: draftTaskID, shouldNotifySync: false)

        let localState = context.collect(ownerID: ownerID)

        #expect(localState.localDraftTaskTags.map(\.id) == [RecordID("\(draftTaskID):\(tag.id)")])
        #expect(localState.dirtyTaskTags.isEmpty)
        #expect(localState.invalidDirtyTaskTagIDs.isEmpty)
        #expect(!localState.hasDirtyChanges)
    }

    // Behaviour: task dependency rows that would make a task depend on itself
    // should be cleaned up locally instead of being pushed.
    @Test("Invalid task dependency is excluded from push state")
    func invalidTaskDependencyIsExcludedFromPushState() throws {
        let context = makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = try #require(context.taskStore.addTask(
            id: "task-1",
            name: "Task",
            createdAt: now,
            updatedAt: now,
            shouldNotifySync: false
        ))
        let selfDependency = TaskTaskDependency(
            taskId: task.id,
            dependsOnTaskId: task.id,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )

        try context.taskDependencyStore.persistReplacedAll(
            taskTaskDependencies: [selfDependency],
            taskRecurringTaskDependencies: []
        )
        context.syncStateStore.markDirty(
            userID: ownerID,
            kind: .taskTaskDependencies,
            ids: [selfDependency.id]
        )

        let localState = context.collect(ownerID: ownerID)

        #expect(localState.dirtyTaskTaskDependencies.isEmpty)
        #expect(localState.invalidDirtyTaskTaskDependencyIDs == [selfDependency.id])
    }
}
