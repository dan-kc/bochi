import Foundation
import Testing
@testable import bochi

@MainActor
struct SyncCompletionFinalizerTests {
    private let ownerID = "user-123"
    private let timestamp = "2026-04-18T12:00:00.000000"

    @MainActor
    private struct TestContext {
        let syncStateStore: SyncStateStore
        let timerStore: TimerStore
        let taskStore: TaskStore
        let taskDependencyStore: TaskDependencyStore
        let rewardDependencyStore: RewardDependencyStore
        let recurringTaskStore: RecurringTaskStore
        let rewardStore: RewardStore
        let tradeStore: TradeStore
        let tagStore: TagStore

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

        var finalizer: SyncCompletionFinalizer {
            SyncCompletionFinalizer(
                syncStateStore: syncStateStore,
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
    }

    // Behaviour: after a successful sync, deleted rows included in the sync
    // snapshot can be purged, but newer local deletions must remain dirty.
    @Test("Successful completion purges only synced tombstones")
    func successfulCompletionPurgesOnlySyncedTombstones() throws {
        let context = makeContext()
        let syncedDeletedTaskID = RecordID("synced-delete")
        let newerDeletedTaskID = RecordID("newer-delete")
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_000)

        _ = try #require(context.taskStore.addTask(
            id: syncedDeletedTaskID,
            name: "Already pushed delete",
            createdAt: deletedAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt,
            shouldNotifySync: false
        ))
        _ = try #require(context.taskStore.addTask(
            id: newerDeletedTaskID,
            name: "Deleted during sync",
            createdAt: deletedAt,
            updatedAt: deletedAt,
            deletedAt: deletedAt,
            shouldNotifySync: false
        ))
        context.syncStateStore.markDirty(userID: ownerID, kind: .tasks, ids: [syncedDeletedTaskID])
        let syncStateSnapshot = context.syncStateStore.state(for: ownerID)
        let localState = context.collector.collect(from: syncStateSnapshot)
        context.syncStateStore.markDirty(userID: ownerID, kind: .tasks, ids: [newerDeletedTaskID])

        let serverTime = try context.finalizer.finalizeSuccessfulSync(
            userID: ownerID,
            syncStateSnapshot: syncStateSnapshot,
            checkpointResponse: makeResponse(),
            localState: localState,
            completedFullSync: false
        )

        context.taskStore.setCurrentOwner(ownerID)
        let finalSyncState = context.syncStateStore.state(for: ownerID)

        #expect(context.taskStore.tasks.map(\.id) == [newerDeletedTaskID])
        #expect(finalSyncState.dirty.tasks.map(\.id) == [newerDeletedTaskID])
        #expect(finalSyncState.lastSyncCursor == "cursor-123")
        #expect(finalSyncState.lastSyncTime == serverTime)
    }

    private func makeContext() -> TestContext {
        let storageURL = TestHelpers.makeTemporaryFileURL("sync-completion-finalizer")
        let timerStore = TimerStore(storageURL: storageURL)
        timerStore.setCurrentOwner(ownerID)
        return TestContext(
            syncStateStore: SyncStateStore(storageURL: storageURL),
            timerStore: timerStore,
            taskStore: TaskStore(storageURL: storageURL, initialOwnerID: ownerID),
            taskDependencyStore: TaskDependencyStore(storageURL: storageURL, initialOwnerID: ownerID),
            rewardDependencyStore: RewardDependencyStore(storageURL: storageURL, initialOwnerID: ownerID),
            recurringTaskStore: RecurringTaskStore(storageURL: storageURL, initialOwnerID: ownerID),
            rewardStore: RewardStore(storageURL: storageURL, initialOwnerID: ownerID),
            tradeStore: TradeStore(storageURL: storageURL, initialOwnerID: ownerID),
            tagStore: TagStore(storageURL: storageURL, initialOwnerID: ownerID)
        )
    }

    private func makeResponse() -> SyncResponse {
        SyncResponse(
            timers: [],
            tasks: [],
            recurringTasks: [],
            trades: [],
            tags: [],
            taskTags: [],
            taskTaskDependencies: [],
            taskRecurringTaskDependencies: [],
            recurringTaskTags: [],
            rewards: [],
            rewardTaskDependencies: [],
            rewardRecurringTaskDependencies: [],
            rewardTags: [],
            balance: SyncBalanceRecord(pointBalance: 0),
            serverCursor: "cursor-123",
            serverTime: timestamp,
            email: "user@example.com",
            isPremium: false,
            themePalettes: .default
        )
    }
}
