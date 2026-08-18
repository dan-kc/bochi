import Foundation
import Testing
@testable import bochi

@MainActor
struct SyncModelMappingTests {
    // Behaviour: backend timestamps carry microseconds, so sync formatting must
    // not drop fractional precision before conflict resolution sees the value.
    @Test func backendTimestampRoundTripsMicroseconds() throws {
        let timestamp = "2026-04-23T12:00:00.123456"

        let parsed = try #require(AppDateCoding.parseBackendTimestamp(timestamp))

        #expect(AppDateCoding.backendTimestamp(from: parsed) == timestamp)
    }

    // Behaviour: vault trades must keep their kind and interest hour through
    // sync so balance projections can be derived from the ledger on every device.
    @Test func syncTradeRecordRoundTripsVaultFields() throws {
        let record = SyncTradeRecord(
            id: "trade-1",
            taskId: nil,
            recurringTaskId: nil,
            rewardId: nil,
            sourceName: "Vault interest",
            amount: 0,
            vaultAmountMicro: 25_500,
            tradeKind: .vaultInterest,
            vaultInterestHour: "2025-01-02T03:00:00.000000",
            createdAt: "2025-01-02T03:00:00.000000",
            updatedAt: "2025-01-02T03:00:00.000000",
            deletedAt: nil,
            refundsTradeId: nil
        )

        let model = try #require(record.toModel())
        #expect(model.tradeKind == .vaultInterest)
        #expect(model.amount == 0)
        #expect(model.vaultAmountMicro == 25_500)
        #expect(model.vaultInterestHour == AppDateCoding.parseBackendTimestamp("2025-01-02T03:00:00.000000"))

        let encoded = SyncTradeRecord.from(model)
        #expect(encoded.tradeKind == .vaultInterest)
        #expect(encoded.amount == 0)
        #expect(encoded.vaultAmountMicro == 25_500)
        #expect(encoded.vaultInterestHour == "2025-01-02T03:00:00.000000")
    }

    // Behaviour: named timers must round-trip through sync with every interval
    // intact so interval timers work the same on each signed-in device.
    @Test func syncTimerRecordRoundTripsIntervals() throws {
        let record = SyncTimerRecord(
            id: "timer-1",
            name: "Tabata",
            intervals: [
                TimerInterval(name: "Work", durationSeconds: 20),
                TimerInterval(name: "Rest", durationSeconds: 10)
            ],
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-23T12:30:00.000000",
            deletedAt: nil
        )

        let model = try #require(record.toModel())
        #expect(model.name == "Tabata")
        #expect(model.intervals.map(\.name) == ["Work", "Rest"])
        #expect(model.intervals.map(\.durationSeconds) == [20, 10])

        let encoded = SyncTimerRecord.from(model)
        #expect(encoded.id == "timer-1")
        #expect(encoded.intervals == record.intervals)
        #expect(encoded.updatedAt == "2026-04-23T12:30:00.000000")
    }

    // Behaviour: task sync payloads should preserve editable task fields while
    // completion stays derived from task trades.
    @Test func syncTaskRecordRoundTripsTaskFields() throws {
        let record = SyncTaskRecord(
            id: "task-1",
            name: "Submit report",
            description: "",
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-23T12:00:00.000000",
            deletedAt: nil,
            basePrice: 275,
            dueDate: "2026-04-25T09:00:00.000000",
            pinned: true,
            hidden: true
        )

        let model = try #require(record.toModel())
        #expect(model.basePrice == 275)
        #expect(model.dueDate == AppDateCoding.parseBackendTimestamp("2026-04-25T09:00:00.000000"))
        #expect(model.pinned)
        #expect(model.hidden)

        let encoded = SyncTaskRecord.from(model)
        #expect(encoded.basePrice == 275)
        #expect(encoded.dueDate == "2026-04-25T09:00:00.000000")
        #expect(encoded.pinned)
        #expect(encoded.hidden)
    }

    // Behaviour: sync payloads should fail fast when a backend-owned integer is
    // outside the Postgres i32 range instead of creating a row that can never push back.
    @Test func syncTaskRecordRejectsOutOfRangeBasePrice() throws {
        let json = """
        {
          "id": "task-1",
          "name": "Submit report",
          "description": "",
          "createdAt": "2026-04-23T12:00:00.000000",
          "updatedAt": "2026-04-23T12:00:00.000000",
          "deletedAt": null,
          "basePrice": \(BackendIntegerContract.max + 1),
          "dueDate": null,
          "pinned": false,
          "hidden": false
        }
        """.data(using: .utf8)!

        do {
            _ = try JSONDecoder().decode(SyncTaskRecord.self, from: json)
            Issue.record("Expected out-of-range backend basePrice to fail decoding.")
        } catch {
            #expect(true)
        }
    }

    // Behaviour: encoding dirty local rows should also enforce the backend
    // integer contract before the network request is sent.
    @Test func syncTradeRecordRejectsOutOfRangeAmountWhenEncoding() throws {
        let record = SyncTradeRecord(
            id: "trade-1",
            taskId: "task-1",
            recurringTaskId: nil,
            rewardId: nil,
            sourceName: "Task",
            amount: BackendIntegerContract.max + 1,
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-23T12:00:00.000000",
            deletedAt: nil,
            refundsTradeId: nil
        )

        do {
            _ = try JSONEncoder().encode(record)
            Issue.record("Expected out-of-range backend amount to fail encoding.")
        } catch {
            #expect(true)
        }
    }

    // Behaviour: sync task payloads should also accept backend timestamps that
    // omit fractional seconds.
    @Test func syncTaskRecordParsesDueDateWithoutFractionalSeconds() throws {
        let record = SyncTaskRecord(
            id: "task-1",
            name: "Submit report",
            description: "",
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-23T12:00:00.000000",
            deletedAt: nil,
            basePrice: 200,
            dueDate: "2026-04-25T09:00:00"
        )

        let model = try #require(record.toModel())
        #expect(model.dueDate == AppDateCoding.parseBackendTimestamp("2026-04-25T09:00:00"))
    }

    // Behaviour: when the backend sends the lowest allowed recurringTask frequency,
    // the sync layer should keep the exact daily-rate value the pricing logic uses.
    @Test func syncRecurringTaskRecordPreservesOnePerMonthFrequency() throws {
        let rate = 1.0 / 30.0
        let record = SyncRecurringTaskRecord(
            id: "recurringTask-1",
            name: "Stretch",
            description: "",
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-23T12:00:00.000000",
            deletedAt: nil,
            minDailyFrequency: rate,
            lockoutDurationSeconds: nil,
            basePrice: 125,
            pinned: true,
            hidden: true
        )

        let model = try #require(record.toModel())
        #expect(model.frequency == rate)
        #expect(model.basePrice == 125)
        #expect(model.pinned)
        #expect(model.hidden)
    }

    // Behaviour: timer assignments on task sync records should preserve both
    // saved named timers and duration-backed timers.
    @Test func syncTaskRecordRoundTripsTimerSelection() throws {
        let namedRecord = SyncTaskRecord(
            id: "task-1",
            name: "Submit report",
            description: "",
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-23T12:00:00.000000",
            deletedAt: nil,
            basePrice: 200,
            dueDate: nil,
            timerMode: "named",
            timerId: "timer-1"
        )
        let namedTask = try #require(namedRecord.toModel())
        #expect(namedTask.timerSelection == EntityTimerSelection.named(RecordID("timer-1")))

        let namedEncoded = SyncTaskRecord.from(namedTask)
        #expect(namedEncoded.timerMode == "named")
        #expect(namedEncoded.timerId == "timer-1")

        let durationRecord = SyncTaskRecord(
            id: "task-2",
            name: "Read",
            description: "",
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-23T12:00:00.000000",
            deletedAt: nil,
            basePrice: 150,
            dueDate: nil,
            timerMode: "duration"
        )
        let durationTask = try #require(durationRecord.toModel())
        #expect(durationTask.timerSelection == EntityTimerSelection.duration)

        let durationEncoded = SyncTaskRecord.from(durationTask)
        #expect(durationEncoded.timerMode == "duration")
        #expect(durationEncoded.timerId == nil)
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
            lockoutDurationSeconds: 7_200,
            basePrice: 450,
            pinned: true,
            hidden: true
        )

        let model = try #require(record.toModel())
        #expect(model.maxFrequency == rate)
        #expect(model.lockoutDurationSeconds == 7_200)
        #expect(model.basePrice == 450)
        #expect(model.pinned)
        #expect(model.hidden)
    }

    // Behaviour: encoding local entities back to the wire format should keep
    // fractional daily rates and submitted base prices.
    @Test func syncRecordsFromModelsPreserveFrequencyAndBasePrice() {
        let rate = 1.0 / 30.0
        let now = Date(timeIntervalSince1970: 1_745_411_200)
        let recurringTask = RecurringTask(
            id: "recurringTask-1",
            name: "Stretch",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            frequency: rate,
            basePrice: 125
        )
        let reward = Reward(
            id: "reward-1",
            name: "Chocolate",
            description: "",
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            maxFrequency: rate,
            lockoutDurationSeconds: 7_200,
            basePrice: 450
        )

        let recurringTaskRecord = SyncRecurringTaskRecord.from(recurringTask)
        let rewardRecord = SyncRewardRecord.from(reward)

        #expect(recurringTaskRecord.minDailyFrequency == rate)
        #expect(recurringTaskRecord.basePrice == 125)
        #expect(rewardRecord.maxDailyFrequency == rate)
        #expect(rewardRecord.lockoutDurationSeconds == 7_200)
        #expect(rewardRecord.basePrice == 450)
    }

    // Behaviour: refund trades must round-trip through sync so the app can
    // keep explicit refund ledger rows consistent across devices.
    @Test func syncTradeRecordRoundTripsRefundsTradeID() throws {
        let refundsTradeId = "trade-0"
        let record = SyncTradeRecord(
            id: "trade-1",
            taskId: "task-1",
            recurringTaskId: nil,
            rewardId: nil,
            sourceName: "Submit report",
            amount: 120,
            createdAt: "2026-04-23T12:00:00.000000",
            updatedAt: "2026-04-24T08:00:00.000000",
            deletedAt: nil,
            refundsTradeId: refundsTradeId
        )

        let model = try #require(record.toModel())
        #expect(model.refundsTradeId == RecordID(refundsTradeId))
        #expect(model.sourceName == "Submit report")

        let encoded = SyncTradeRecord.from(model)
        #expect(encoded.refundsTradeId == refundsTradeId)
        #expect(encoded.sourceName == "Submit report")
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
        let recurringTaskDependency = SyncTaskRecurringTaskDependencyRecord(
            taskId: "task-2",
            recurringTaskId: "recurringTask-1",
            requiredCompletions: 3,
            baselineCompletionCount: 5,
            createdAt: "2026-04-23T12:05:00.000000",
            updatedAt: "2026-04-23T12:05:00.000000",
            deletedAt: nil
        )

        let taskDependencyModel = try #require(taskDependency.toModel())
        let recurringTaskDependencyModel = try #require(recurringTaskDependency.toModel())

        #expect(taskDependencyModel.dependsOnTaskId == "task-1")
        #expect(recurringTaskDependencyModel.requiredCompletions == 3)
        #expect(recurringTaskDependencyModel.baselineCompletionCount == 5)

        #expect(SyncTaskTaskDependencyRecord.from(taskDependencyModel).dependsOnTaskId == "task-1")
        #expect(SyncTaskRecurringTaskDependencyRecord.from(recurringTaskDependencyModel).requiredCompletions == 3)
        #expect(SyncTaskRecurringTaskDependencyRecord.from(recurringTaskDependencyModel).baselineCompletionCount == 5)
    }

    // Behaviour: the JSON decoder used by the sync client should decode
    // camelCase frequency and base-price payloads without loss.
    @Test func syncResponseDecodesBoundaryFrequenciesAndBasePrices() throws {
        let rate = 1.0 / 30.0
        let json = """
        {
          "timers": [],
          "tasks": [
            {
              "id": "task-1",
              "name": "Submit report",
              "description": "",
              "createdAt": "2026-04-23T12:00:00.000000",
              "updatedAt": "2026-04-23T12:00:00.000000",
              "deletedAt": null,
              "basePrice": 275,
              "dueDate": "2026-04-24T09:00:00.000000",
              "pinned": false,
              "hidden": false
            }
          ],
          "recurringTasks": [
            {
              "id": "recurringTask-1",
              "name": "Stretch",
              "description": "",
              "createdAt": "2026-04-23T12:00:00.000000",
              "updatedAt": "2026-04-23T12:00:00.000000",
              "deletedAt": null,
              "minDailyFrequency": \(rate),
              "lockoutDurationSeconds": null,
              "basePrice": 125,
              "pinned": false,
              "hidden": false
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
          "taskRecurringTaskDependencies": [
            {
              "taskId": "task-2",
              "recurringTaskId": "recurringTask-1",
              "requiredCompletions": 2,
              "baselineCompletionCount": 1,
              "createdAt": "2026-04-23T12:11:00.000000",
              "updatedAt": "2026-04-23T12:11:00.000000",
              "deletedAt": null
            }
          ],
          "recurringTaskTags": [],
          "rewards": [
            {
              "id": "reward-1",
              "name": "Chocolate",
              "description": "",
              "createdAt": "2026-04-23T12:00:00.000000",
              "updatedAt": "2026-04-23T12:00:00.000000",
              "deletedAt": null,
              "recurring": true,
              "maxDailyFrequency": \(rate),
              "lockoutDurationSeconds": null,
              "basePrice": 450,
              "pinned": false,
              "hidden": false
            }
          ],
          "rewardTaskDependencies": [],
          "rewardRecurringTaskDependencies": [],
          "rewardTags": [],
          "balance": {
            "pointBalance": 0
          },
          "serverCursor": "cursor-123",
          "serverTime": "2026-04-23T12:00:00.000000",
          "email": "user@example.com",
          "isPremium": false,
          "themePalettes": {
            "main": "porcelain",
            "accent": "semantic"
          }
        }
        """

        let response = try AppDateCoding.makeDecoder().decode(SyncResponse.self, from: Data(json.utf8))

        #expect(response.tasks.first?.basePrice == 275)
        #expect(response.tasks.first?.dueDate == "2026-04-24T09:00:00.000000")
        #expect(response.taskTags.first?.taskId == "task-1")
        #expect(response.taskTaskDependencies.first?.dependsOnTaskId == "task-1")
        #expect(response.taskRecurringTaskDependencies.first?.requiredCompletions == 2)
        #expect(response.recurringTasks.first?.minDailyFrequency == rate)
        #expect(response.recurringTasks.first?.basePrice == 125)
        #expect(response.rewards.first?.maxDailyFrequency == rate)
        #expect(response.rewards.first?.basePrice == 450)
        #expect(response.themePalettes.main == .porcelain)
        #expect(response.themePalettes.accent == .semantic)
        #expect(response.balance.pointBalance == 0)
    }

    // Behaviour: the sync response contract is strict; visibility flags are
    // backend-owned fields, so missing values should fail instead of defaulting.
    @Test func syncTaskRecordRejectsMissingVisibilityFields() throws {
        let json = """
        {
          "id": "task-1",
          "name": "Submit report",
          "description": "",
          "createdAt": "2026-04-23T12:00:00.000000",
          "updatedAt": "2026-04-23T12:00:00.000000",
          "deletedAt": null,
          "basePrice": 100,
          "dueDate": null
        }
        """.data(using: .utf8)!

        do {
            _ = try JSONDecoder().decode(SyncTaskRecord.self, from: json)
            Issue.record("Expected task response without visibility flags to fail decoding.")
        } catch {
            #expect(true)
        }
    }

    // Behaviour: server trade timestamps should be explicit. Falling back to
    // createdAt would hide a malformed sync response and corrupt conflict data.
    @Test func syncTradeRecordRejectsMissingUpdatedAt() throws {
        let json = """
        {
          "id": "trade-1",
          "taskId": "task-1",
          "recurringTaskId": null,
          "rewardId": null,
          "sourceName": "Task",
          "amount": 100,
          "vaultAmountMicro": null,
          "adjustmentBaseAmount": null,
          "oneTimeAdjustmentMultiplier": null,
          "tradeKind": "taskCompletion",
          "vaultInterestHour": null,
          "createdAt": "2026-04-23T12:00:00.000000",
          "deletedAt": null,
          "refundsTradeId": null
        }
        """.data(using: .utf8)!

        do {
            _ = try JSONDecoder().decode(SyncTradeRecord.self, from: json)
            Issue.record("Expected trade response without updatedAt to fail decoding.")
        } catch {
            #expect(true)
        }
    }
}
