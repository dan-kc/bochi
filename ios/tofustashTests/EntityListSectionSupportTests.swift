import Foundation
import Testing
@testable import tofustash

@MainActor
struct EntityListSectionSupportTests {
    // Behaviour: Tasks should stay in one scrollable list while still grouping
    // actionable, blocked, and completed work under stable section headers.
    @Test("task sections group rows by actionable state")
    func taskSectionsGroupByState() {
        let storageURL = TestHelpers.makeTemporaryFileURL("task-section-support")
        let taskStore = TaskStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let dependencyStore = TaskDependencyStore(storageURL: storageURL)

        let openTask = taskStore.addTask(name: "Open task")!
        let prerequisiteTask = taskStore.addTask(name: "Prerequisite")!
        let blockedTask = taskStore.addTask(name: "Blocked task")!
        let completedTask = taskStore.addTask(name: "Completed task")!

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
            habitDependencies: [],
            shouldNotifySync: false
        )

        taskStore.completeTask(
            id: completedTask.id,
            completedAt: Date(timeIntervalSince1970: 1_800_000_200),
            shouldNotifySync: false
        )
        tradeStore.addTaskTrade(
            taskId: completedTask.id,
            amount: 120,
            createdAt: Date(timeIntervalSince1970: 1_800_000_200),
            shouldNotifySync: false
        )

        let sections = EntityListSectionSupport.taskSections(
            tasks: [openTask, blockedTask, completedTask],
            taskStore: taskStore,
            tradeStore: tradeStore,
            taskDependencyStore: dependencyStore
        )

        #expect(sections.map(\.title) == [nil, "Blocked by dependency", "Completed"])
        #expect(sections[0].items.map(\.id) == [openTask.id])
        #expect(sections[1].items.map(\.id) == [blockedTask.id])
        #expect(sections[2].items.map(\.id) == [completedTask.id])
        #expect(sections[0].isDimmed == false)
        #expect(sections[1].isDimmed == true)
        #expect(sections[2].isDimmed == true)
    }

    // Behaviour: Empty sections should disappear so the list only shows
    // categories that actually have visible rows.
    @Test("empty sections are omitted")
    func emptySectionsAreOmitted() {
        let storageURL = TestHelpers.makeTemporaryFileURL("habit-section-support")
        let tradeStore = TradeStore(storageURL: storageURL)
        let habit = Habit(
            id: "habit-1",
            name: "Stretch",
            description: "",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            deletedAt: nil,
            frequency: nil,
            difficultyTier: nil
        )

        let habitSections = EntityListSectionSupport.habitSections(
            habits: [habit],
            tradeStore: tradeStore
        )

        #expect(habitSections.map(\.title) == [nil])
    }

    // Behaviour: Rewards should move into the locked section as soon as a
    // recent purchase triggers their cooldown.
    @Test("reward sections group locked rewards separately")
    func rewardSectionsGroupLockedRewards() {
        let storageURL = TestHelpers.makeTemporaryFileURL("reward-section-support")
        let tradeStore = TradeStore(storageURL: storageURL)
        let openReward = Reward(
            id: "reward-open",
            name: "Open Reward",
            description: "",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            deletedAt: nil,
            maxFrequency: nil,
            damageTier: nil,
            lockoutDurationSeconds: nil
        )
        let lockedReward = Reward(
            id: "reward-locked",
            name: "Locked Reward",
            description: "",
            createdAt: Date(timeIntervalSince1970: 1_800_000_100),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
            deletedAt: nil,
            maxFrequency: nil,
            damageTier: nil,
            lockoutDurationSeconds: 3_600
        )

        tradeStore.addRewardPurchase(
            rewardId: lockedReward.id,
            amount: -100,
            createdAt: Date().addingTimeInterval(-300),
            shouldNotifySync: false
        )

        let sections = EntityListSectionSupport.rewardSections(
            rewards: [openReward, lockedReward],
            tradeStore: tradeStore
        )

        #expect(sections.map(\.title) == [nil, "Locked"])
        #expect(sections[0].items.map(\.id) == [openReward.id])
        #expect(sections[1].items.map(\.id) == [lockedReward.id])
        #expect(sections[1].isDimmed == true)
    }
}
