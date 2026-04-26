import Foundation
import Testing
@testable import tofustash

struct SyncModelMappingTests {
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

    // Behaviour: the JSON decoder used by the sync client should decode
    // camelCase frequency payloads into Double-backed sync records without loss.
    @Test func syncResponseDecodesBoundaryFrequenciesAsDouble() throws {
        let rate = 1.0 / 30.0
        let json = """
        {
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
        #expect(response.habits.first?.minDailyFrequency == rate)
        #expect(response.rewards.first?.maxDailyFrequency == rate)
    }
}
