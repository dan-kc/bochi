import Foundation
import Testing
@testable import tofustash

@MainActor
struct TaskDependencyStoreTests {
    private func makeStorageURL() -> URL {
        TestHelpers.makeTemporaryFileURL("task-dependencies")
    }

    // Behaviour: a task should stay blocked until every task and habit
    // dependency is satisfied, including habit completions that must happen
    // after the dependency was assigned.
    @Test func taskBlockedStateTracksTaskAndHabitDependencies() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let habitStore = HabitStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)

        let prerequisiteTask = try #require(taskStore.addTask(name: "Draft report"))
        let blockedTask = try #require(taskStore.addTask(name: "Send report"))
        let habit = try #require(habitStore.addHabit(name: "Proofread"))

        tradeStore.addHabitTradeWithDate(
            habitId: habit.id,
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
            habitDependencies: [
                TaskHabitDependency(
                    taskId: blockedTask.id,
                    habitId: habit.id,
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

        taskStore.completeTask(
            id: prerequisiteTask.id,
            completedAt: Date(timeIntervalSince1970: 1_800_000_300),
            shouldNotifySync: false
        )
        #expect(
            dependencyStore.isTaskBlocked(
                blockedTask,
                taskStore: taskStore,
                tradeStore: tradeStore
            )
        )

        tradeStore.addHabitTradeWithDate(
            habitId: habit.id,
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

        tradeStore.addHabitTradeWithDate(
            habitId: habit.id,
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

    // Behaviour: editing a habit dependency count should restart progress from
    // the current completion total so "2 more" always means 2 more from now.
    @Test func updatingHabitDependencyRequiredCompletionsResetsBaselineToCurrentTradeCount() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let habitStore = HabitStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)

        let task = try #require(taskStore.addTask(name: "Ship build"))
        let habit = try #require(habitStore.addHabit(name: "Run smoke test"))

        for offset in 0..<3 {
            tradeStore.addHabitTradeWithDate(
                habitId: habit.id,
                amount: 1000,
                createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(offset))
            )
        }

        dependencyStore.replaceDependencies(
            for: task.id,
            taskDependencies: [],
            habitDependencies: [
                TaskHabitDependency(
                    taskId: task.id,
                    habitId: habit.id,
                    requiredCompletions: 1,
                    baselineCompletionCount: 3,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_100),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
                    deletedAt: nil
                )
            ],
            shouldNotifySync: false
        )

        tradeStore.addHabitTradeWithDate(
            habitId: habit.id,
            amount: 1000,
            createdAt: Date(timeIntervalSince1970: 1_800_000_200)
        )

        dependencyStore.updateHabitDependencyRequiredCompletions(
            taskId: task.id,
            habitId: habit.id,
            requiredCompletions: 2,
            tradeStore: tradeStore,
            shouldNotifySync: false
        )

        let updated = try #require(
            dependencyStore
                .activeHabitDependencies(for: task.id)
                .first(where: { $0.habitId == habit.id })
        )
        #expect(updated.requiredCompletions == 2)
        #expect(updated.baselineCompletionCount == 4)
    }

    // Behaviour: deleting a task should tombstone every dependency row that
    // references it so downstream tasks stop being blocked before sync runs.
    @Test func deletingTaskRemovesAllLinksToThatTask() throws {
        let storageURL = makeStorageURL()
        let taskStore = TaskStore(storageURL: storageURL)
        let habitStore = HabitStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)

        let prerequisiteTask = try #require(taskStore.addTask(name: "Draft report"))
        let deletedTask = try #require(taskStore.addTask(name: "Review report"))
        let downstreamTask = try #require(taskStore.addTask(name: "Send report"))
        let habit = try #require(habitStore.addHabit(name: "Proofread"))
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_900)

        dependencyStore.replaceDependencies(
            for: deletedTask.id,
            taskDependencies: [
                TaskTaskDependency(
                    taskId: deletedTask.id,
                    dependsOnTaskId: prerequisiteTask.id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_100),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
                    deletedAt: nil
                )
            ],
            habitDependencies: [
                TaskHabitDependency(
                    taskId: deletedTask.id,
                    habitId: habit.id,
                    requiredCompletions: 1,
                    baselineCompletionCount: 0,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_200),
                    updatedAt: Date(timeIntervalSince1970: 1_800_000_200),
                    deletedAt: nil
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
                    deletedAt: nil
                )
            ],
            habitDependencies: [],
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

        let deletedHabitDependencies = dependencyStore.taskHabitDependencies.filter { $0.taskId == deletedTask.id }
        #expect(deletedHabitDependencies.count == 1)
        #expect(deletedHabitDependencies.allSatisfy { $0.deletedAt == deletedAt })

        #expect(
            !dependencyStore.isTaskBlocked(
                downstreamTask,
                taskStore: taskStore,
                tradeStore: tradeStore
            )
        )
    }
}
