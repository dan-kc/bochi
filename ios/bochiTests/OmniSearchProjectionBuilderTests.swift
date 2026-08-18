import Foundation
import Testing
@testable import bochi

struct OmniSearchProjectionBuilderTests {
    // Behaviour: the search overlay should render completed, locked, spent, and
    // refundable row states from one consistent data snapshot.
    @Test("Projection builder preserves row states used by omni search")
    func projectionBuilderPreservesSearchRowStates() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let prerequisiteTask = makeTask(id: "task-prerequisite", name: "Read first")
        let blockedTask = makeTask(id: "task-blocked", name: "Read blocked")
        let completedTask = makeTask(id: "task-completed", name: "Read completed")
        let recurringTask = makeRecurringTask(
            id: "recurringTask-locked",
            name: "Read recurring",
            lockoutDurationSeconds: 3_600
        )
        let spentReward = makeReward(id: "reward-spent", recurring: false, name: "Read treat")
        let blockedReward = makeReward(id: "reward-blocked", name: "Read locked reward")
        let purchaseTrade = makeTrade(
            id: "reward-trade",
            rewardId: spentReward.id,
            amount: -100,
            createdAt: now.addingTimeInterval(-300)
        )
        let completedTrade = makeTrade(
            id: "task-trade",
            taskId: completedTask.id,
            amount: 100,
            createdAt: now.addingTimeInterval(-200)
        )

        let projection = OmniSearchProjectionBuilder.makeProjection(
            inputs: OmniSearchProjectionInputs(
                queryText: "read",
                preferences: EntityListPreferences(),
                tasks: [prerequisiteTask, blockedTask, completedTask],
                recurringTasks: [recurringTask],
                rewards: [spentReward, blockedReward],
                taskTagsByID: [:],
                recurringTaskTagsByID: [:],
                rewardTagsByID: [:],
                taskTaskDependencies: [
                    TaskTaskDependency(
                        taskId: blockedTask.id,
                        dependsOnTaskId: prerequisiteTask.id,
                        createdAt: now,
                        updatedAt: now,
                        deletedAt: nil
                    )
                ],
                taskRecurringTaskDependencies: [],
                rewardTaskDependencies: [
                    RewardTaskDependency(
                        rewardId: blockedReward.id,
                        dependsOnTaskId: prerequisiteTask.id,
                        createdAt: now,
                        updatedAt: now,
                        deletedAt: nil
                    )
                ],
                rewardRecurringTaskDependencies: [],
                latestTaskTradesByTaskID: [completedTask.id: completedTrade],
                recurringTaskCompletionCountsByRecurringTaskID: [:],
                recurringTaskTradeDatesByRecurringTaskID: [
                    recurringTask.id: [now.addingTimeInterval(-60)]
                ],
                rewardPurchaseDatesByRewardID: [
                    spentReward.id: [purchaseTrade.createdAt]
                ],
                latestRewardPurchasesByRewardID: [spentReward.id: purchaseTrade],
                hasPremiumAccess: true,
                now: now
            )
        )

        let blockedTaskRow = try #require(projection.rowsByID[.task(blockedTask.id)]?.taskRow)
        let completedTaskRow = try #require(projection.rowsByID[.task(completedTask.id)]?.taskRow)
        let recurringTaskRow = try #require(projection.rowsByID[.recurringTask(recurringTask.id)]?.recurringTaskRow)
        let spentRewardRow = try #require(projection.rowsByID[.reward(spentReward.id)]?.rewardRow)
        let blockedRewardRow = try #require(projection.rowsByID[.reward(blockedReward.id)]?.rewardRow)

        #expect(blockedTaskRow.isBlocked)
        #expect(!blockedTaskRow.isCompleted)
        #expect(completedTaskRow.isCompleted)
        #expect(!completedTaskRow.canComplete)
        #expect(recurringTaskRow.isLocked)
        #expect(spentRewardRow.isSpent)
        #expect(spentRewardRow.canRefund)
        #expect(blockedRewardRow.isBlocked)
    }

    private func makeTask(id: RecordID, name: String) -> TaskItem {
        let createdAt = Date(timeIntervalSince1970: 86_400)
        return TaskItem(
            id: id,
            name: name,
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            dueDate: nil
        )
    }

    private func makeRecurringTask(
        id: RecordID,
        name: String,
        lockoutDurationSeconds: Int? = nil
    ) -> RecurringTask {
        let createdAt = Date(timeIntervalSince1970: 86_400)
        return RecurringTask(
            id: id,
            name: name,
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            frequency: nil,
            lockoutDurationSeconds: lockoutDurationSeconds
        )
    }

    private func makeReward(
        id: RecordID,
        recurring: Bool = true,
        name: String
    ) -> Reward {
        let createdAt = Date(timeIntervalSince1970: 86_400)
        return Reward(
            id: id,
            recurring: recurring,
            name: name,
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            maxFrequency: nil
        )
    }

    private func makeTrade(
        id: RecordID,
        taskId: RecordID? = nil,
        rewardId: RecordID? = nil,
        amount: Int,
        createdAt: Date
    ) -> Trade {
        Trade(
            id: id,
            taskId: taskId,
            recurringTaskId: nil,
            rewardId: rewardId,
            amount: amount,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }
}

private extension OmniSearchRowModel {
    var taskRow: OmniSearchTaskRowModel? {
        guard case .task(let row) = self else { return nil }
        return row
    }

    var recurringTaskRow: OmniSearchRecurringTaskRowModel? {
        guard case .recurringTask(let row) = self else { return nil }
        return row
    }

    var rewardRow: OmniSearchRewardRowModel? {
        guard case .reward(let row) = self else { return nil }
        return row
    }
}
