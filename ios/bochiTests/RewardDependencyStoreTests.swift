import Foundation
import Testing
@testable import bochi

@MainActor
struct RewardDependencyStoreTests {
    private func makeStorageURL() -> URL {
        TestHelpers.makeTemporaryFileURL("reward-dependencies")
    }

    // Behaviour: rewards stay locked until every task and recurringTask prerequisite is
    // complete, and recurringTask progress is measured from the saved baseline.
    @Test func rewardBlockedStateTracksTaskAndRecurringTaskDependencies() throws {
        let storageURL = makeStorageURL()
        let rewardStore = RewardStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = RewardDependencyStore(storageURL: storageURL)

        let reward = try #require(rewardStore.addReward(id: "reward-1", name: "Dessert"))
        let task = try #require(taskStore.addTask(id: "task-1", name: "Finish work"))
        let recurringTask = try #require(recurringTaskStore.addRecurringTask(id: "recurringTask-1", name: "Walk"))

        dependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [
                RewardTaskDependency(
                    rewardId: reward.id,
                    dependsOnTaskId: task.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil
                )
            ],
            recurringTaskDependencies: [
                RewardRecurringTaskDependency(
                    rewardId: reward.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 2,
                    baselineCompletionCount: 0,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil
                )
            ],
            shouldNotifySync: false
        )

        #expect(dependencyStore.isRewardBlocked(reward, taskStore: taskStore, tradeStore: tradeStore))

        tradeStore.addTaskTrade(taskId: task.id, amount: 100, createdAt: Date(timeIntervalSince1970: 1_800_000_100), shouldNotifySync: false)
        tradeStore.addRecurringTaskTrade(recurringTaskId: recurringTask.id, amount: 100, createdAt: Date(timeIntervalSince1970: 1_800_000_200), shouldNotifySync: false)

        #expect(dependencyStore.isRewardBlocked(reward, taskStore: taskStore, tradeStore: tradeStore))

        tradeStore.addRecurringTaskTrade(recurringTaskId: recurringTask.id, amount: 100, createdAt: Date(timeIntervalSince1970: 1_800_000_300), shouldNotifySync: false)

        #expect(!dependencyStore.isRewardBlocked(reward, taskStore: taskStore, tradeStore: tradeStore))
    }

    // Behaviour: lapsed premium users keep saved reward dependency rows, but
    // those rows should not hide reward purchase while premium is off.
    @Test func lapsedPremiumIgnoresRewardDependenciesForPurchaseBlocking() throws {
        let storageURL = makeStorageURL()
        let rewardStore = RewardStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = RewardDependencyStore(storageURL: storageURL)

        let reward = try #require(rewardStore.addReward(id: "reward-1", name: "Dessert"))
        let task = try #require(taskStore.addTask(id: "task-1", name: "Finish work"))
        dependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [
                RewardTaskDependency(
                    rewardId: reward.id,
                    dependsOnTaskId: task.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil
                )
            ],
            recurringTaskDependencies: [],
            shouldNotifySync: false
        )

        #expect(dependencyStore.isRewardBlocked(
            reward,
            taskStore: taskStore,
            tradeStore: tradeStore,
            hasPremiumAccess: true
        ))
        #expect(!dependencyStore.isRewardBlocked(
            reward,
            taskStore: taskStore,
            tradeStore: tradeStore,
            hasPremiumAccess: false
        ))
    }

    // Behaviour: reward recurringTask progress keeps counting while premium is off so
    // re-subscribing shows the user's current unlock progress.
    @Test func recurringTaskDependencyProgressContinuesWhilePremiumIsLapsed() throws {
        let storageURL = makeStorageURL()
        let rewardStore = RewardStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = RewardDependencyStore(storageURL: storageURL)

        let reward = try #require(rewardStore.addReward(id: "reward-1", name: "Dessert"))
        let recurringTask = try #require(recurringTaskStore.addRecurringTask(id: "recurringTask-1", name: "Walk"))
        dependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [],
            recurringTaskDependencies: [
                RewardRecurringTaskDependency(
                    rewardId: reward.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 3,
                    baselineCompletionCount: 0,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil
                )
            ],
            shouldNotifySync: false
        )

        tradeStore.addRecurringTaskTrade(recurringTaskId: recurringTask.id, amount: 100, shouldNotifySync: false)
        let dependency = try #require(dependencyStore.activeRecurringTaskDependencies(for: reward.id).first)
        #expect(dependencyStore.recurringTaskDependencyProgress(for: dependency, tradeStore: tradeStore) == 1)

        tradeStore.addRecurringTaskTrade(recurringTaskId: recurringTask.id, amount: 100, shouldNotifySync: false)

        #expect(dependencyStore.recurringTaskDependencyProgress(for: dependency, tradeStore: tradeStore) == 2)
    }

    // Behaviour: deleting a prerequisite task should tombstone reward task
    // dependencies that point at it so rewards are not left blocked by a hidden row.
    @Test func deletingTaskRemovesRewardDependenciesReferencingThatTask() throws {
        let storageURL = makeStorageURL()
        let rewardStore = RewardStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = RewardDependencyStore(storageURL: storageURL)
        let deletedAt = Date(timeIntervalSince1970: 1_800_001_000)

        let reward = try #require(rewardStore.addReward(id: "reward-1", name: "Dessert"))
        let task = try #require(taskStore.addTask(id: "task-1", name: "Finish work"))
        dependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [
                RewardTaskDependency(
                    rewardId: reward.id,
                    dependsOnTaskId: task.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil,
                    serverRevision: 31
                )
            ],
            recurringTaskDependencies: [],
            shouldNotifySync: false
        )

        #expect(dependencyStore.isRewardBlocked(reward, taskStore: taskStore, tradeStore: tradeStore))

        dependencyStore.deleteDependenciesReferencingTask(task.id, deletedAt: deletedAt, shouldNotifySync: false)
        taskStore.deleteTask(id: task.id, deletedAt: deletedAt, shouldNotifySync: false)

        let dependency = try #require(dependencyStore.rewardTaskDependencies.first)
        #expect(dependency.deletedAt == deletedAt)
        #expect(dependency.serverRevision == 31)
        #expect(!dependencyStore.isRewardBlocked(reward, taskStore: taskStore, tradeStore: tradeStore))
    }

    // Behaviour: deleting a reward should tombstone every dependency row owned
    // by that reward so later sync does not resurrect stale prerequisites.
    @Test func deletingRewardRemovesAllRewardDependencyRows() throws {
        let storageURL = makeStorageURL()
        let rewardStore = RewardStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let dependencyStore = RewardDependencyStore(storageURL: storageURL)
        let deletedAt = Date(timeIntervalSince1970: 1_800_001_100)

        let reward = try #require(rewardStore.addReward(id: "reward-1", name: "Dessert"))
        let task = try #require(taskStore.addTask(id: "task-1", name: "Finish work"))
        let recurringTask = try #require(recurringTaskStore.addRecurringTask(id: "recurringTask-1", name: "Walk"))
        dependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [
                RewardTaskDependency(
                    rewardId: reward.id,
                    dependsOnTaskId: task.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil,
                    serverRevision: 41
                )
            ],
            recurringTaskDependencies: [
                RewardRecurringTaskDependency(
                    rewardId: reward.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 2,
                    baselineCompletionCount: 0,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil,
                    serverRevision: 42
                )
            ],
            shouldNotifySync: false
        )

        dependencyStore.deleteDependenciesReferencingReward(reward.id, deletedAt: deletedAt, shouldNotifySync: false)
        rewardStore.deleteReward(id: reward.id, deletedAt: deletedAt, shouldNotifySync: false)

        #expect(dependencyStore.rewardTaskDependencies.count == 1)
        #expect(dependencyStore.rewardRecurringTaskDependencies.count == 1)
        #expect(dependencyStore.rewardTaskDependencies.allSatisfy { $0.deletedAt == deletedAt })
        #expect(dependencyStore.rewardRecurringTaskDependencies.allSatisfy { $0.deletedAt == deletedAt })
        #expect(dependencyStore.rewardTaskDependencies.first?.serverRevision == 41)
        #expect(dependencyStore.rewardRecurringTaskDependencies.first?.serverRevision == 42)
        #expect(dependencyStore.hasDependencies(for: reward.id) == false)
    }

    // Behaviour: buying a dependency-gated reward should consume completed
    // recurringTask progress by moving the baseline to the current completion count.
    @Test func resetRecurringTaskDependenciesMovesBaselineToCurrentCompletionCount() throws {
        let storageURL = makeStorageURL()
        let rewardStore = RewardStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = RewardDependencyStore(storageURL: storageURL)

        let reward = try #require(rewardStore.addReward(id: "reward-1", name: "Dessert"))
        let recurringTask = try #require(recurringTaskStore.addRecurringTask(id: "recurringTask-1", name: "Walk"))
        dependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [],
            recurringTaskDependencies: [
                RewardRecurringTaskDependency(
                    rewardId: reward.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 2,
                    baselineCompletionCount: 0,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil,
                    serverRevision: 0
                )
            ],
            shouldNotifySync: false
        )
        tradeStore.addRecurringTaskTrade(recurringTaskId: recurringTask.id, amount: 100, shouldNotifySync: false)
        tradeStore.addRecurringTaskTrade(recurringTaskId: recurringTask.id, amount: 100, shouldNotifySync: false)

        dependencyStore.resetRecurringTaskDependencies(for: reward.id, tradeStore: tradeStore, shouldNotifySync: false)

        let dependency = try #require(dependencyStore.activeRecurringTaskDependencies(for: reward.id).first)
        #expect(dependency.requiredCompletions == 2)
        #expect(dependency.baselineCompletionCount == 2)
        #expect(dependency.serverRevision == 0)
        #expect(dependencyStore.recurringTaskDependencyProgress(for: dependency, tradeStore: tradeStore) == 0)
    }

    // Behaviour: editing dependencies that were loaded from sync should keep
    // their base revision so later pushes update the server row instead of
    // attempting a duplicate insert.
    @Test func replacingSyncedRewardDependenciesPreservesServerRevisions() throws {
        let storageURL = makeStorageURL()
        let rewardStore = RewardStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let dependencyStore = RewardDependencyStore(storageURL: storageURL)

        let reward = try #require(rewardStore.addReward(id: "reward-1", name: "Dessert"))
        let task = try #require(taskStore.addTask(id: "task-1", name: "Finish work"))
        let recurringTask = try #require(recurringTaskStore.addRecurringTask(id: "recurringTask-1", name: "Walk"))
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let editedAt = Date(timeIntervalSince1970: 1_800_000_100)

        dependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [
                RewardTaskDependency(
                    rewardId: reward.id,
                    dependsOnTaskId: task.id,
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    deletedAt: nil,
                    serverRevision: 0
                )
            ],
            recurringTaskDependencies: [
                RewardRecurringTaskDependency(
                    rewardId: reward.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 2,
                    baselineCompletionCount: 0,
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    deletedAt: nil,
                    serverRevision: 52
                )
            ],
            shouldNotifySync: false
        )

        dependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [
                RewardTaskDependency(
                    rewardId: reward.id,
                    dependsOnTaskId: task.id,
                    createdAt: createdAt,
                    updatedAt: editedAt,
                    deletedAt: nil
                )
            ],
            recurringTaskDependencies: [
                RewardRecurringTaskDependency(
                    rewardId: reward.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 3,
                    baselineCompletionCount: 1,
                    createdAt: createdAt,
                    updatedAt: editedAt,
                    deletedAt: nil
                )
            ],
            shouldNotifySync: false
        )

        let updatedTaskDependency = try #require(dependencyStore.activeTaskDependencies(for: reward.id).first)
        let updatedRecurringDependency = try #require(dependencyStore.activeRecurringTaskDependencies(for: reward.id).first)
        #expect(updatedTaskDependency.serverRevision == 0)
        #expect(updatedRecurringDependency.serverRevision == 52)

        dependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [],
            recurringTaskDependencies: [],
            shouldNotifySync: false
        )

        let deletedTaskDependency = try #require(dependencyStore.rewardTaskDependencies.first)
        let deletedRecurringDependency = try #require(dependencyStore.rewardRecurringTaskDependencies.first)
        #expect(deletedTaskDependency.deletedAt != nil)
        #expect(deletedRecurringDependency.deletedAt != nil)
        #expect(deletedTaskDependency.serverRevision == 0)
        #expect(deletedRecurringDependency.serverRevision == 52)
    }

    // Behaviour: reward dependency edits should persist across app relaunch so
    // rewards keep their prerequisites after the process restarts.
    @Test func rewardDependenciesPersistAcrossStoreRelaunch() throws {
        let storageURL = makeStorageURL()
        let rewardStore = RewardStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let firstStore = RewardDependencyStore(storageURL: storageURL)

        let reward = try #require(rewardStore.addReward(id: "reward-1", name: "Dessert"))
        let task = try #require(taskStore.addTask(id: "task-1", name: "Finish work"))
        let recurringTask = try #require(recurringTaskStore.addRecurringTask(id: "recurringTask-1", name: "Walk"))
        firstStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [
                RewardTaskDependency(
                    rewardId: reward.id,
                    dependsOnTaskId: task.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil
                )
            ],
            recurringTaskDependencies: [
                RewardRecurringTaskDependency(
                    rewardId: reward.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 3,
                    baselineCompletionCount: 1,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    deletedAt: nil
                )
            ],
            shouldNotifySync: false
        )

        let reloadedStore = RewardDependencyStore(storageURL: storageURL)

        #expect(reloadedStore.activeTaskDependencies(for: reward.id).map(\.dependsOnTaskId) == [task.id])
        let recurringTaskDependency = try #require(reloadedStore.activeRecurringTaskDependencies(for: reward.id).first)
        #expect(recurringTaskDependency.recurringTaskId == recurringTask.id)
        #expect(recurringTaskDependency.requiredCompletions == 3)
        #expect(recurringTaskDependency.baselineCompletionCount == 1)
    }

    // Behaviour: dependency changes should mark both added and removed rows as
    // dirty so sync can push the full local edit.
    @Test func replacingRewardDependenciesMarksAddedAndRemovedRowsDirty() throws {
        let storageURL = makeStorageURL()
        let rewardStore = RewardStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let dependencyStore = RewardDependencyStore(storageURL: storageURL)
        let syncStateStore = SyncStateStore(storageURL: storageURL)
        dependencyStore.setCurrentOwner("user-1")

        let reward = try #require(rewardStore.addReward(id: "reward-1", name: "Dessert"))
        let task = try #require(taskStore.addTask(id: "task-1", name: "Finish work"))
        let recurringTask = try #require(recurringTaskStore.addRecurringTask(id: "recurringTask-1", name: "Walk"))
        let taskDependency = RewardTaskDependency(
            rewardId: reward.id,
            dependsOnTaskId: task.id,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            deletedAt: nil
        )
        let recurringTaskDependency = RewardRecurringTaskDependency(
            rewardId: reward.id,
            recurringTaskId: recurringTask.id,
            requiredCompletions: 2,
            baselineCompletionCount: 0,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
            deletedAt: nil
        )

        dependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [taskDependency],
            recurringTaskDependencies: [recurringTaskDependency]
        )
        dependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [],
            recurringTaskDependencies: [recurringTaskDependency]
        )

        let dirtyState = syncStateStore.state(for: "user-1").dirty
        #expect(dirtyState.rewardTaskDependencies.map(\.id).contains(taskDependency.id))
        #expect(dirtyState.rewardRecurringTaskDependencies.map(\.id).contains(recurringTaskDependency.id))
        #expect(dependencyStore.rewardTaskDependencies.first?.deletedAt != nil)
    }
}
