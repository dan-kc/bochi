import Foundation
import Testing
@testable import bochi

@MainActor
struct TaskDependencyStoreTests {
    private func makeStorageURL() -> URL {
        TestHelpers.makeTemporaryFileURL("task-dependencies")
    }

    // Behaviour: a task should stay blocked until every task and recurringTask
    // dependency is satisfied, including recurringTask completions that must happen
    // after the dependency was assigned.
    @Test func taskBlockedStateTracksTaskAndRecurringTaskDependencies() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)

        let prerequisiteTask = try #require(taskStore.addTask(name: "Draft report"))
        let blockedTask = try #require(taskStore.addTask(name: "Send report"))
        let recurringTask = try #require(recurringTaskStore.addRecurringTask(name: "Proofread"))

        tradeStore.addRecurringTaskTradeWithDate(
            recurringTaskId: recurringTask.id,
            amount: 1000,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        dependencyStore.replaceDependencies(
            for: blockedTask.id,
            taskDependencies: [
                TaskTaskDependency(
                    taskId: blockedTask.id,
                    dependsOnTaskId: prerequisiteTask.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_100),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
                    deletedAt: nil
                )
            ],
            recurringTaskDependencies: [
                TaskRecurringTaskDependency(
                    taskId: blockedTask.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 2,
                    baselineCompletionCount: 1,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_200),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_200),
                    deletedAt: nil
                )
            ],
            shouldNotifySync: false
        )

        #expect(
            dependencyStore.isTaskBlocked(
                blockedTask,
                taskStore: taskStore,
                tradeStore: tradeStore
            )
        )

        tradeStore.addTaskTrade(
            taskId: prerequisiteTask.id,
            amount: 100,
            createdAt: Date(timeIntervalSince1970: 1_800_000_300),
            shouldNotifySync: false
        )
        #expect(
            dependencyStore.isTaskBlocked(
                blockedTask,
                taskStore: taskStore,
                tradeStore: tradeStore
            )
        )

        tradeStore.addRecurringTaskTradeWithDate(
            recurringTaskId: recurringTask.id,
            amount: 1000,
            createdAt: Date(timeIntervalSince1970: 1_800_000_400)
        )
        #expect(
            dependencyStore.isTaskBlocked(
                blockedTask,
                taskStore: taskStore,
                tradeStore: tradeStore
            )
        )

        tradeStore.addRecurringTaskTradeWithDate(
            recurringTaskId: recurringTask.id,
            amount: 1000,
            createdAt: Date(timeIntervalSince1970: 1_800_000_500)
        )
        #expect(
            !dependencyStore.isTaskBlocked(
                blockedTask,
                taskStore: taskStore,
                tradeStore: tradeStore
            )
        )
    }

    // Behaviour: lapsed premium users keep their dependency rows, but those
    // rows should not stop them from completing the task while premium is off.
    @Test func lapsedPremiumIgnoresTaskDependenciesForCompletionBlocking() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)

        let prerequisiteTask = try #require(taskStore.addTask(name: "Draft report"))
        let blockedTask = try #require(taskStore.addTask(name: "Send report"))
        dependencyStore.replaceDependencies(
            for: blockedTask.id,
            taskDependencies: [
                TaskTaskDependency(
                    taskId: blockedTask.id,
                    dependsOnTaskId: prerequisiteTask.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_100),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
                    deletedAt: nil
                )
            ],
            recurringTaskDependencies: [],
            shouldNotifySync: false
        )

        #expect(
            dependencyStore.isTaskBlocked(
                blockedTask,
                taskStore: taskStore,
                tradeStore: tradeStore,
                hasPremiumAccess: true
            )
        )
        #expect(
            !dependencyStore.isTaskBlocked(
                blockedTask,
                taskStore: taskStore,
                tradeStore: tradeStore,
                hasPremiumAccess: false
            )
        )
    }

    // Behaviour: recurringTask dependency progress keeps counting completions while
    // premium is off so re-subscribing restores the user's real progress.
    @Test func recurringTaskDependencyProgressContinuesWhilePremiumIsLapsed() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)

        let task = try #require(taskStore.addTask(name: "Ship build"))
        let recurringTask = try #require(recurringTaskStore.addRecurringTask(name: "Run smoke test"))
        dependencyStore.replaceDependencies(
            for: task.id,
            taskDependencies: [],
            recurringTaskDependencies: [
                TaskRecurringTaskDependency(
                    taskId: task.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 3,
                    baselineCompletionCount: 0,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_100),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
                    deletedAt: nil
                )
            ],
            shouldNotifySync: false
        )

        tradeStore.addRecurringTaskTradeWithDate(
            recurringTaskId: recurringTask.id,
            amount: 1000,
            createdAt: Date(timeIntervalSince1970: 1_800_000_200)
        )
        let dependency = try #require(dependencyStore.activeRecurringTaskDependencies(for: task.id).first)
        #expect(dependencyStore.recurringTaskDependencyProgress(for: dependency, tradeStore: tradeStore) == 1)

        tradeStore.addRecurringTaskTradeWithDate(
            recurringTaskId: recurringTask.id,
            amount: 1000,
            createdAt: Date(timeIntervalSince1970: 1_800_000_300)
        )

        #expect(dependencyStore.recurringTaskDependencyProgress(for: dependency, tradeStore: tradeStore) == 2)
    }

    // Behaviour: editing a recurringTask dependency count should restart progress from
    // the current completion total so "2 more" always means 2 more from now.
    @Test func updatingRecurringTaskDependencyRequiredCompletionsResetsBaselineToCurrentTradeCount() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)

        let task = try #require(taskStore.addTask(name: "Ship build"))
        let recurringTask = try #require(recurringTaskStore.addRecurringTask(name: "Run smoke test"))

        for offset in 0..<3 {
            tradeStore.addRecurringTaskTradeWithDate(
                recurringTaskId: recurringTask.id,
                amount: 1000,
                createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(offset))
            )
        }

        dependencyStore.replaceDependencies(
            for: task.id,
            taskDependencies: [],
            recurringTaskDependencies: [
                TaskRecurringTaskDependency(
                    taskId: task.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 1,
                    baselineCompletionCount: 3,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_100),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
                    deletedAt: nil,
                    serverRevision: 0
                )
            ],
            shouldNotifySync: false
        )

        tradeStore.addRecurringTaskTradeWithDate(
            recurringTaskId: recurringTask.id,
            amount: 1000,
            createdAt: Date(timeIntervalSince1970: 1_800_000_200)
        )

        dependencyStore.updateRecurringTaskDependencyRequiredCompletions(
            taskId: task.id,
            recurringTaskId: recurringTask.id,
            requiredCompletions: 2,
            tradeStore: tradeStore,
            shouldNotifySync: false
        )

        let updated = try #require(
            dependencyStore
                .activeRecurringTaskDependencies(for: task.id)
                .first(where: { $0.recurringTaskId == recurringTask.id })
        )
        #expect(updated.requiredCompletions == 2)
        #expect(updated.baselineCompletionCount == 4)
        #expect(updated.serverRevision == 0)
    }

    // Behaviour: editing or removing dependency rows loaded from the server
    // should keep their base revision so sync sends an update, not a create.
    @Test func replacingSyncedTaskDependenciesPreservesServerRevisions() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)

        let prerequisiteTask = try #require(taskStore.addTask(name: "Draft report"))
        let task = try #require(taskStore.addTask(name: "Send report"))
        let recurringTask = try #require(recurringTaskStore.addRecurringTask(name: "Proofread"))
        let createdAt = Date(timeIntervalSince1970: 1_800_000_100)
        let editedAt = Date(timeIntervalSince1970: 1_800_000_200)

        let syncedTaskDependency = TaskTaskDependency(
            taskId: task.id,
            dependsOnTaskId: prerequisiteTask.id,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            serverRevision: 0
        )
        let syncedRecurringTaskDependency = TaskRecurringTaskDependency(
            taskId: task.id,
            recurringTaskId: recurringTask.id,
            requiredCompletions: 1,
            baselineCompletionCount: 0,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            serverRevision: 12
        )
        dependencyStore.replaceDependencies(
            for: task.id,
            taskDependencies: [syncedTaskDependency],
            recurringTaskDependencies: [syncedRecurringTaskDependency],
            shouldNotifySync: false
        )

        dependencyStore.replaceDependencies(
            for: task.id,
            taskDependencies: [
                TaskTaskDependency(
                    taskId: task.id,
                    dependsOnTaskId: prerequisiteTask.id,
                    createdAt: createdAt,
                    updatedAt: editedAt,
                    deletedAt: nil
                )
            ],
            recurringTaskDependencies: [
                TaskRecurringTaskDependency(
                    taskId: task.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 2,
                    baselineCompletionCount: 1,
                    createdAt: createdAt,
                    updatedAt: editedAt,
                    deletedAt: nil
                )
            ],
            shouldNotifySync: false
        )

        #expect(dependencyStore.taskTaskDependencies.first?.serverRevision == 0)
        #expect(dependencyStore.taskRecurringTaskDependencies.first?.serverRevision == 12)

        dependencyStore.replaceDependencies(
            for: task.id,
            taskDependencies: [],
            recurringTaskDependencies: [],
            shouldNotifySync: false
        )

        #expect(dependencyStore.taskTaskDependencies.first?.deletedAt != nil)
        #expect(dependencyStore.taskTaskDependencies.first?.serverRevision == 0)
        #expect(dependencyStore.taskRecurringTaskDependencies.first?.deletedAt != nil)
        #expect(dependencyStore.taskRecurringTaskDependencies.first?.serverRevision == 12)
    }

    // Behaviour: deleting a task should tombstone every dependency row that
    // references it so downstream tasks stop being blocked before sync runs.
    @Test func deletingTaskRemovesAllLinksToThatTask() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)

        let prerequisiteTask = try #require(taskStore.addTask(name: "Draft report"))
        let deletedTask = try #require(taskStore.addTask(name: "Review report"))
        let downstreamTask = try #require(taskStore.addTask(name: "Send report"))
        let recurringTask = try #require(recurringTaskStore.addRecurringTask(name: "Proofread"))
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_900)

        dependencyStore.replaceDependencies(
            for: deletedTask.id,
            taskDependencies: [
                TaskTaskDependency(
                    taskId: deletedTask.id,
                    dependsOnTaskId: prerequisiteTask.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_100),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
                    deletedAt: nil,
                    serverRevision: 21
                )
            ],
            recurringTaskDependencies: [
                TaskRecurringTaskDependency(
                    taskId: deletedTask.id,
                    recurringTaskId: recurringTask.id,
                    requiredCompletions: 1,
                    baselineCompletionCount: 0,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_200),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_200),
                    deletedAt: nil,
                    serverRevision: 22
                )
            ],
            shouldNotifySync: false
        )
        dependencyStore.replaceDependencies(
            for: downstreamTask.id,
            taskDependencies: [
                TaskTaskDependency(
                    taskId: downstreamTask.id,
                    dependsOnTaskId: deletedTask.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_300),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_300),
                    deletedAt: nil,
                    serverRevision: 23
                )
            ],
            recurringTaskDependencies: [],
            shouldNotifySync: false
        )

        #expect(
            dependencyStore.isTaskBlocked(
                downstreamTask,
                taskStore: taskStore,
                tradeStore: tradeStore
            )
        )

        dependencyStore.deleteDependenciesReferencingTask(
            deletedTask.id,
            deletedAt: deletedAt,
            shouldNotifySync: false
        )
        taskStore.deleteTask(id: deletedTask.id, deletedAt: deletedAt, shouldNotifySync: false)

        let deletedTaskTaskDependencies = dependencyStore.taskTaskDependencies.filter {
            $0.taskId == deletedTask.id || $0.dependsOnTaskId == deletedTask.id
        }
        #expect(deletedTaskTaskDependencies.count == 2)
        #expect(deletedTaskTaskDependencies.allSatisfy { $0.deletedAt == deletedAt })
        #expect(Set(deletedTaskTaskDependencies.compactMap(\.serverRevision)) == [21, 23])

        let deletedRecurringTaskDependencies = dependencyStore.taskRecurringTaskDependencies.filter { $0.taskId == deletedTask.id }
        #expect(deletedRecurringTaskDependencies.count == 1)
        #expect(deletedRecurringTaskDependencies.allSatisfy { $0.deletedAt == deletedAt })
        #expect(deletedRecurringTaskDependencies.allSatisfy { $0.serverRevision == 22 })

        #expect(
            !dependencyStore.isTaskBlocked(
                downstreamTask,
                taskStore: taskStore,
                tradeStore: tradeStore
            )
        )
    }
}
