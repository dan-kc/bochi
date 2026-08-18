import Foundation
import Testing
@testable import bochi

@MainActor
struct SyncPayloadMapperTests {
    private let timestamp = "2026-04-18T12:00:00.000000"

    // Behaviour: rows edited locally after a sync request starts must not be
    // overwritten when the older server response arrives.
    @Test("Dirty snapshot excludes protected server records")
    func dirtySnapshotExcludesProtectedServerRecords() throws {
        var dirtyIDs = SyncDirtyIDSnapshot()
        dirtyIDs.tasks[RecordID("dirty-task")] = 3
        dirtyIDs.taskTags[RecordID("dirty-task:tag-1")] = 4

        let payload = try SyncPayloadMapper.makePayload(
            from: makeResponse(
                tasks: [
                    makeTaskRecord(id: "dirty-task", name: "Older server task", serverRevision: 10),
                    makeTaskRecord(id: "clean-task", name: "Fresh server task", serverRevision: 11)
                ],
                taskTags: [
                    makeTaskTagRecord(taskID: "dirty-task", tagID: "tag-1", serverRevision: 12),
                    makeTaskTagRecord(taskID: "clean-task", tagID: "tag-1", serverRevision: 13)
                ]
            ),
            excluding: dirtyIDs
        )

        #expect(payload.tasks.map(\.id) == [RecordID("clean-task")])
        #expect(payload.tasks.first?.serverRevision == 11)
        #expect(payload.taskTags.map(\.id) == [RecordID("clean-task:tag-1")])
        #expect(payload.taskTags.first?.serverRevision == 13)
    }

    // Behaviour: malformed server rows should fail the sync visibly instead of
    // being dropped and making the local device look silently up to date.
    @Test("Malformed server record throws a sync payload error")
    func malformedServerRecordThrowsSyncPayloadError() throws {
        let response = makeResponse(
            timers: [
                SyncTimerRecord(
                    id: "timer-1",
                    name: "Tabata",
                    intervals: [],
                    createdAt: "not-a-date",
                    updatedAt: timestamp,
                    deletedAt: nil
                )
            ]
        )

        do {
            _ = try SyncPayloadMapper.makePayload(from: response)
            Issue.record("Expected a malformed timer to throw before persistence.")
        } catch let error as SyncPayloadMappingError {
            switch error {
            case let .malformedRecord(kind, id):
                #expect(kind == "timer")
                #expect(id == "timer-1")
            }
        } catch {
            Issue.record("Expected SyncPayloadMappingError, got \(error).")
        }
    }

    private func makeResponse(
        timers: [SyncTimerRecord] = [],
        tasks: [SyncTaskRecord] = [],
        taskTags: [SyncTaskTagRecord] = []
    ) -> SyncResponse {
        SyncResponse(
            timers: timers,
            tasks: tasks,
            recurringTasks: [],
            trades: [],
            tags: [],
            taskTags: taskTags,
            taskTaskDependencies: [],
            taskRecurringTaskDependencies: [],
            recurringTaskTags: [],
            rewards: [],
            rewardTaskDependencies: [],
            rewardRecurringTaskDependencies: [],
            rewardTags: [],
            balance: SyncBalanceRecord(pointBalance: 0),
            serverCursor: "cursor-123",
            serverTime: timestamp,
            email: "user@example.com",
            isPremium: false,
            themePalettes: .default
        )
    }

    private func makeTaskRecord(
        id: String,
        name: String,
        serverRevision: Int64
    ) -> SyncTaskRecord {
        SyncTaskRecord(
            id: id,
            name: name,
            description: "",
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil,
            basePrice: 200,
            dueDate: nil,
            serverRevision: serverRevision
        )
    }

    private func makeTaskTagRecord(
        taskID: String,
        tagID: String,
        serverRevision: Int64
    ) -> SyncTaskTagRecord {
        SyncTaskTagRecord(
            taskId: taskID,
            tagId: tagID,
            createdAt: timestamp,
            updatedAt: timestamp,
            deletedAt: nil,
            serverRevision: serverRevision
        )
    }
}
