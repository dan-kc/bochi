import Foundation
import Testing
@testable import bochi

struct SpendListProjectionBuilderTests {
    // Behaviour: the Spend list should derive affordability, dependency-blocked,
    // and spent/refundable row states from one consistent store snapshot.
    @Test("Spend projection builder preserves reward row states")
    func spendProjectionBuilderPreservesRowStates() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let prerequisiteTask = makeTask(id: "task-prerequisite", name: "Read first")
        let affordableReward = makeReward(id: "reward-affordable", name: "Affordable read", basePrice: 100)
        let expensiveReward = makeReward(id: "reward-expensive", name: "Expensive read", basePrice: 500)
        let spentReward = makeReward(id: "reward-spent", recurring: false, name: "Spent read", basePrice: 100)
        let blockedReward = makeReward(id: "reward-blocked", name: "Blocked read", basePrice: 100)
        let purchaseTrade = makeTrade(
            id: "reward-trade",
            rewardId: spentReward.id,
            amount: -100,
            createdAt: now.addingTimeInterval(-300)
        )

        let projection = SpendListProjectionBuilder.makeProjection(
            inputs: RewardListProjectionInputs(
                rewards: [affordableReward, expensiveReward, spentReward, blockedReward],
                tasks: [prerequisiteTask],
                rewardTagsByID: [:],
                activeTagIDs: [],
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
                latestTaskTradesByTaskID: [:],
                recurringTaskCompletionCountsByRecurringTaskID: [:],
                rewardPurchaseDatesByRewardID: [spentReward.id: [purchaseTrade.createdAt]],
                latestRewardPurchasesByRewardID: [spentReward.id: purchaseTrade],
                balance: 150,
                preferences: EntityListPreferences(),
                hasPremiumAccess: true,
                now: now
            )
        )

        let affordableRewardRow = try #require(projection.visibleRewardRows.first { $0.id == affordableReward.id })
        let expensiveRewardRow = try #require(projection.visibleRewardRows.first { $0.id == expensiveReward.id })
        let spentRewardRow = try #require(projection.visibleRewardRows.first { $0.id == spentReward.id })
        let blockedRewardRow = try #require(projection.visibleRewardRows.first { $0.id == blockedReward.id })

        #expect(affordableRewardRow.canAfford)
        #expect(!expensiveRewardRow.canAfford)
        #expect(spentRewardRow.isSpent)
        #expect(spentRewardRow.canRefund)
        #expect(!spentRewardRow.canAfford)
        #expect(blockedRewardRow.isBlocked)
        #expect(!blockedRewardRow.canAfford)
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

    private func makeReward(
        id: RecordID,
        recurring: Bool = true,
        name: String,
        basePrice: Int
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
            maxFrequency: nil,
            basePrice: basePrice
        )
    }

    private func makeTrade(
        id: RecordID,
        rewardId: RecordID,
        amount: Int,
        createdAt: Date
    ) -> Trade {
        Trade(
            id: id,
            taskId: nil,
            recurringTaskId: nil,
            rewardId: rewardId,
            amount: amount,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }
}
