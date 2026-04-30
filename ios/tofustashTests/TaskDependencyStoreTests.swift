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
}
