import Foundation
import Testing
@testable import tofustash

@MainActor
struct SyncModelMappingTests {
    // Behaviour: task sync payloads should preserve due date and completion
    // state exactly so the local task list matches the server snapshot.
    @Test func syncTaskRecordRoundTripsTaskFields() throws {
        let record = SyncTaskRecord(
            id: "task-1",
            name: "Submit report",
            description: "",
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-23T12:00:00.000000",
            deletedAt: nil,
            completedAt: "2026-04-24T08:00:00.000000",
            difficultyTier: .hard,
            durationSeconds: 900,
            skipConsequence: 4,
            dueDate: "2026-04-25T09:00:00.000000"
        )

        let model = try #require(record.toModel())
        #expect(model.completedAt == AppDateCoding.parseBackendTimestamp("2026-04-24T08:00:00.000000"))
        #expect(model.dueDate == AppDateCoding.parseBackendTimestamp("2026-04-25T09:00:00.000000"))

        let encoded = SyncTaskRecord.from(model)
        #expect(encoded.completedAt == "2026-04-24T08:00:00.000000")
        #expect(encoded.dueDate == "2026-04-25T09:00:00.000000")
    }

    // Behaviour: sync task payloads should also accept backend timestamps
    // that omit fractional seconds, because the server sends NaiveDateTime values in that shape too.
    @Test func syncTaskRecordParsesDueDateWithoutFractionalSeconds() throws {
        let record = SyncTaskRecord(
            id: "task-1",
            name: "Submit report",
            description: "",
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-23T12:00:00.000000",
            deletedAt: nil,
            completedAt: nil,
            difficultyTier: .hard,
            durationSeconds: 900,
            skipConsequence: 4,
            dueDate: "2026-04-25T09:00:00"
        )

        let model = try #require(record.toModel())
        #expect(model.dueDate == AppDateCoding.parseBackendTimestamp("2026-04-25T09:00:00"))
    }

    // Behaviour: when the backend sends the lowest allowed habit frequency,
    // the sync layer should keep the exact daily-rate value the pricing logic uses.
    @Test func syncHabitRecordPreservesOnePerMonthFrequency() throws {
        let rate = 1.0 / 30.0
        let record = SyncHabitRecord(
            id: "habit-1",
            name: "Stretch",
            description: "",
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-23T12:00:00.000000",
            deletedAt: nil,
            minDailyFrequency: rate,
            difficultyTier: .light,
            durationSeconds: nil,
            lockoutDurationSeconds: nil,
            skipConsequence: nil
        )

        let model = try #require(record.toModel())
        #expect(model.frequency == rate)
    }

    // Behaviour: when the backend sends the lowest allowed reward frequency,
    // the client should preserve the exact value instead of rounding it down.
    @Test func syncRewardRecordPreservesOnePerMonthFrequency() throws {
        let rate = 1.0 / 30.0
        let record = SyncRewardRecord(
            id: "reward-1",
            name: "Chocolate",
            description: "",
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-23T12:00:00.000000",
            deletedAt: nil,
            maxDailyFrequency: rate,
            damageTier: .medium
        )

        let model = try #require(record.toModel())
        #expect(model.maxFrequency == rate)
    }

    // Behaviour: when a locally edited habit is queued for sync, encoding back
    // to the wire format should keep the same fractional daily rate.
    @Test func syncHabitRecordFromModelPreservesFractionalFrequency() {
        let rate = 1.0 / 30.0
        let now = Date(timeIntervalSince1970: 1_745_411_200)
        let habit = Habit(
            id: "habit-1",
            name: "Stretch",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            frequency: rate,
            difficultyTier: .light
        )

        let record = SyncHabitRecord.from(habit)
        #expect(record.minDailyFrequency == rate)
    }

    // Behaviour: refunded trade state must round-trip through sync so the app
    // can keep refunded history visible across devices.
    @Test func syncTradeRecordRoundTripsRefundedAt() throws {
        let refundedAt = "2026-04-24T08:00:00.000000"
        let record = SyncTradeRecord(
            id: "trade-1",
            taskId: "task-1",
            habitId: nil,
            rewardId: nil,
            sourceName: "Submit report",
            amount: 120,
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-24T08:00:00.000000",
            deletedAt: nil,
            refundedAt: refundedAt
        )

        let model = try #require(record.toModel())
        #expect(model.refundedAt == AppDateCoding.parseBackendTimestamp(refundedAt))
        #expect(model.sourceName == "Submit report")

        let encoded = SyncTradeRecord.from(model)
        #expect(encoded.refundedAt == refundedAt)
        #expect(encoded.sourceName == "Submit report")
    }

    // Behaviour: when a locally edited reward is queued for sync, encoding back
    // to the wire format should keep the same fractional daily rate.
    @Test func syncRewardRecordFromModelPreservesFractionalFrequency() {
        let rate = 1.0 / 30.0
        let now = Date(timeIntervalSince1970: 1_745_411_200)
        let reward = Reward(
            id: "reward-1",
            name: "Chocolate",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            maxFrequency: rate,
            damageTier: .medium
        )

        let record = SyncRewardRecord.from(reward)
        #expect(record.maxDailyFrequency == rate)
    }

    // Behaviour: task dependency rows must round-trip through sync unchanged so
    // blocked task state matches the server snapshot exactly.
    @Test func syncTaskDependencyRecordsRoundTrip() throws {
        let taskDependency = SyncTaskTaskDependencyRecord(
            taskId: "task-2",
            dependsOnTaskId: "task-1",
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-23T12:00:00.000000",
            deletedAt: nil
        )
        let habitDependency = SyncTaskHabitDependencyRecord(
            taskId: "task-2",
            habitId: "habit-1",
            requiredCompletions: 3,
            baselineCompletionCount: 5,
            createdAt: "2026-04-23T12:05:00.000000",
            updatedAt: "2026-04-23T12:05:00.000000",
            deletedAt: nil
        )

        let taskDependencyModel = try #require(taskDependency.toModel())
        let habitDependencyModel = try #require(habitDependency.toModel())

        #expect(taskDependencyModel.dependsOnTaskId == "task-1")
        #expect(habitDependencyModel.requiredCompletions == 3)
        #expect(habitDependencyModel.baselineCompletionCount == 5)

        #expect(SyncTaskTaskDependencyRecord.from(taskDependencyModel).dependsOnTaskId == "task-1")
        #expect(SyncTaskHabitDependencyRecord.from(habitDependencyModel).requiredCompletions == 3)
        #expect(SyncTaskHabitDependencyRecord.from(habitDependencyModel).baselineCompletionCount == 5)
    }

    // Behaviour: the JSON decoder used by the sync client should decode
    // camelCase frequency payloads into Double-backed sync records without loss.
    @Test func syncResponseDecodesBoundaryFrequenciesAsDouble() throws {
        let rate = 1.0 / 30.0
        let json = """
        {
          "tasks": [
            {
              "id": "task-1",
              "name": "Submit report",
              "description": "",
              "createdAt": "2026-04-23T12:00:00.000000",
              "updatedAt": "2026-04-23T12:00:00.000000",
              "deletedAt": null,
              "completedAt": null,
              "difficultyTier": "light",
              "durationSeconds": 600,
              "skipConsequence": 2,
              "dueDate": "2026-04-24T09:00:00.000000"
            }
          ],
          "habits": [
            {
              "id": "habit-1",
              "name": "Stretch",
              "description": "",
              "createdAt": "2026-04-23T12:00:00.000000",
              "updatedAt": "2026-04-23T12:00:00.000000",
              "deletedAt": null,
              "minDailyFrequency": \(rate),
              "difficultyTier": "light",
              "durationSeconds": null,
              "lockoutDurationSeconds": null,
              "skipConsequence": null
            }
          ],
          "trades": [],
          "tags": [],
          "taskTags": [
            {
              "taskId": "task-1",
              "tagId": "tag-1",
              "createdAt": "2026-04-23T12:00:00.000000",
              "updatedAt": "2026-04-23T12:00:00.000000",
              "deletedAt": null
            }
          ],
          "taskTaskDependencies": [
            {
              "taskId": "task-2",
              "dependsOnTaskId": "task-1",
              "createdAt": "2026-04-23T12:10:00.000000",
              "updatedAt": "2026-04-23T12:10:00.000000",
              "deletedAt": null
            }
          ],
          "taskHabitDependencies": [
            {
              "taskId": "task-2",
              "habitId": "habit-1",
              "requiredCompletions": 2,
              "baselineCompletionCount": 1,
              "createdAt": "2026-04-23T12:11:00.000000",
              "updatedAt": "2026-04-23T12:11:00.000000",
              "deletedAt": null
            }
          ],
          "habitTags": [],
          "rewards": [
            {
              "id": "reward-1",
              "name": "Chocolate",
              "description": "",
              "createdAt": "2026-04-23T12:00:00.000000",
              "updatedAt": "2026-04-23T12:00:00.000000",
              "deletedAt": null,
              "maxDailyFrequency": \(rate),
              "damageTier": "medium"
            }
          ],
          "rewardTags": [],
          "balance": {
            "tofuBalance": 0
          },
          "serverCursor": "cursor-123",
          "serverTime": "2026-04-23T12:00:00.000000",
          "email": "user@example.com",
          "isPremium": false,
          "generalDifficulty": 5.0
        }
        """

        let response = try AppDateCoding.makeDecoder().decode(SyncResponse.self, from: Data(json.utf8))
        #expect(response.tasks.first?.dueDate == "2026-04-24T09:00:00.000000")
        #expect(response.taskTags.first?.taskId == "task-1")
        #expect(response.taskTaskDependencies.first?.dependsOnTaskId == "task-1")
        #expect(response.taskHabitDependencies.first?.requiredCompletions == 2)
        #expect(response.habits.first?.minDailyFrequency == rate)
        #expect(response.rewards.first?.maxDailyFrequency == rate)
    }
}
