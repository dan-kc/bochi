import Foundation
import Testing
@testable import bochi

@MainActor
struct RecurringTaskLockoutTests {
    private func makeStore() -> TradeStore {
        TradeStore(storageURL: TestHelpers.makeTemporaryFileURL("recurringTask-lockout-trades"))
    }

    private func makeRecurringTask(
        id: RecordID = "recurringTask-1",
        lockoutDurationSeconds: Int? = nil
    ) -> RecurringTask {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        return RecurringTask(
            id: id,
            name: "Test RecurringTask",
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            frequency: nil,
            lockoutDurationSeconds: lockoutDurationSeconds
        )
    }

    // Behaviour: After a user claims a recurringTask, the lockout should block another
    // claim until the configured window has passed.
    @Test func latestClaimStartsLockoutWindow() {
        let tradeStore = makeStore()
        let recurringTask = makeRecurringTask(lockoutDurationSeconds: 3_600)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        tradeStore.addRecurringTaskTrade(
            recurringTaskId: recurringTask.id,
            amount: 100,
            createdAt: now.addingTimeInterval(-1_800),
            shouldNotifySync: false
        )

        #expect(RecurringTaskLockout.isLocked(recurringTask: recurringTask, tradeStore: tradeStore, now: now) == true)
    }

    // Behaviour: When the lockout period expires, the user should be able to
    // claim the recurringTask again without any manual reset.
    @Test func recurringTaskUnlocksAfterLockoutExpires() {
        let tradeStore = makeStore()
        let recurringTask = makeRecurringTask(lockoutDurationSeconds: 3_600)
        let claimDate = Date(timeIntervalSince1970: 1_800_000_000)

        tradeStore.addRecurringTaskTrade(
            recurringTaskId: recurringTask.id,
            amount: 100,
            createdAt: claimDate,
            shouldNotifySync: false
        )

        #expect(RecurringTaskLockout.isLocked(recurringTask: recurringTask, tradeStore: tradeStore, now: claimDate.addingTimeInterval(3_601)) == false)
    }

    // Behaviour: Deleted claim history should stop locking the recurringTask so the row
    // does not stay disabled after a reverted claim.
    @Test func deletedTradesDoNotKeepRecurringTaskLocked() {
        let tradeStore = makeStore()
        let recurringTask = makeRecurringTask(lockoutDurationSeconds: 3_600)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        tradeStore.addRecurringTaskTrade(
            recurringTaskId: recurringTask.id,
            amount: 100,
            createdAt: now.addingTimeInterval(-600),
            deletedAt: now.addingTimeInterval(-300),
            shouldNotifySync: false
        )

        #expect(RecurringTaskLockout.isLocked(recurringTask: recurringTask, tradeStore: tradeStore, now: now) == false)
    }

    // Behaviour: a lapsed premium user can claim through a saved lockout, but
    // re-enabling premium should immediately resume the lockout from that claim.
    @Test func lapsedPremiumIgnoresLockoutButTracksClaimsForReenabledPremium() {
        let tradeStore = makeStore()
        let recurringTask = makeRecurringTask(lockoutDurationSeconds: 3 * 3_600)
        let claimDate = Date(timeIntervalSince1970: 1_800_000_000)

        tradeStore.addRecurringTaskTrade(
            recurringTaskId: recurringTask.id,
            amount: 100,
            createdAt: claimDate,
            shouldNotifySync: false
        )

        #expect(RecurringTaskLockout.isLocked(
            recurringTask: recurringTask,
            tradeStore: tradeStore,
            now: claimDate,
            hasPremiumAccess: false
        ) == false)
        #expect(RecurringTaskLockout.isLocked(
            recurringTask: recurringTask,
            tradeStore: tradeStore,
            now: claimDate,
            hasPremiumAccess: true
        ) == true)
    }
}
