import Foundation
import Testing
@testable import bochi

struct EarnListProjectionBuilderTests {
    // Behaviour: the Earn list should derive completed, dependency-blocked,
    // and lockout-blocked row states from one consistent store snapshot.
    @Test("Earn projection builder preserves task and recurring task row states")
    func earnProjectionBuilderPreservesRowStates() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let prerequisiteTask = makeTask(id: "task-prerequisite", name: "Read first")
        let blockedTask = makeTask(id: "task-blocked", name: "Read blocked")
        let completedTask = makeTask(id: "task-completed", name: "Read completed")
        let deletedTask = makeTask(id: "task-deleted", name: "Read deleted", deletedAt: now)
        let lockedRecurringTask = makeRecurringTask(
            id: "recurringTask-locked",
            name: "Read recurring",
            lockoutDurationSeconds: 3_600
        )
        let completedTrade = makeTrade(
            id: "task-trade",
            taskId: completedTask.id,
            amount: 100,
            createdAt: now.addingTimeInterval(-300)
        )

        let projection = EarnListProjectionBuilder.makeProjection(
            inputs: EarnListProjectionInputs(
                tasks: [prerequisiteTask, blockedTask, completedTask, deletedTask],
                recurringTasks: [lockedRecurringTask],
                taskTagsByID: [:],
                recurringTaskTagsByID: [:],
                activeTagIDs: [],
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
                latestTaskTradesByTaskID: [completedTask.id: completedTrade],
                recurringTaskCompletionCountsByRecurringTaskID: [:],
                recurringTaskTradeDatesByRecurringTaskID: [
                    lockedRecurringTask.id: [now.addingTimeInterval(-60)]
                ],
                preferences: EntityListPreferences(),
                hasPremiumAccess: true,
                now: now
            )
        )

        let blockedTaskRow = try #require(projection.visibleRows.taskRow(id: blockedTask.id))
        let completedTaskRow = try #require(projection.visibleRows.taskRow(id: completedTask.id))
        let lockedRecurringTaskRow = try #require(projection.visibleRows.recurringTaskRow(id: lockedRecurringTask.id))

        #expect(projection.activeTasks.map(\.id).contains(deletedTask.id) == false)
        #expect(blockedTaskRow.isBlocked)
        #expect(!blockedTaskRow.isCompleted)
        #expect(completedTaskRow.isCompleted)
        #expect(!completedTaskRow.canComplete)
        #expect(lockedRecurringTaskRow.isLocked)
    }

    private func makeTask(
        id: RecordID,
        name: String,
        deletedAt: Date? = nil
    ) -> TaskItem {
        let createdAt = Date(timeIntervalSince1970: 86_400)
        return TaskItem(
            id: id,
            name: name,
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: deletedAt,
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

    private func makeTrade(
        id: RecordID,
        taskId: RecordID,
        amount: Int,
        createdAt: Date
    ) -> Trade {
        Trade(
            id: id,
            taskId: taskId,
            recurringTaskId: nil,
            rewardId: nil,
            amount: amount,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }
}

private extension [EarnListRowModel] {
    func taskRow(id: RecordID) -> EarnTaskRowModel? {
        for row in self {
            guard case .task(let taskRow) = row, taskRow.task.id == id else { continue }
            return taskRow
        }
        return nil
    }

    func recurringTaskRow(id: RecordID) -> EarnRecurringTaskRowModel? {
        for row in self {
            guard case .recurringTask(let recurringTaskRow) = row,
                  recurringTaskRow.recurringTask.id == id
            else { continue }
            return recurringTaskRow
        }
        return nil
    }
}
