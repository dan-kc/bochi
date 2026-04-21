import Foundation
import Testing
@testable import tofustash

@MainActor
struct HabitLockoutTests {
    private func makeStore() -> TradeStore {
        TradeStore(storageURL: TestHelpers.makeTemporaryFileURL("habit-lockout-trades"))
    }

    private func makeHabit(
        id: RecordID = "habit-1",
        lockoutDurationSeconds: Int? = nil
    ) -> Habit {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        return Habit(
            id: id,
            name: "Test Habit",
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            frequency: nil,
            difficultyTier: nil,
            durationSeconds: nil,
            lockoutDurationSeconds: lockoutDurationSeconds,
            skipConsequence: nil
        )
    }

    // Behaviour: After a user claims a habit, the lockout should block another
    // claim until the configured window has passed.
    @Test func latestClaimStartsLockoutWindow() {
        let tradeStore = makeStore()
        let habit = makeHabit(lockoutDurationSeconds: 3_600)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        tradeStore.addHabitTrade(
            habitId: habit.id,
            amount: 100,
            createdAt: now.addingTimeInterval(-1_800),
            shouldNotifySync: false
        )

        #expect(HabitLockout.isLocked(habit: habit, tradeStore: tradeStore, now: now) == true)
    }

    // Behaviour: When the lockout period expires, the user should be able to
    // claim the habit again without any manual reset.
    @Test func habitUnlocksAfterLockoutExpires() {
        let tradeStore = makeStore()
        let habit = makeHabit(lockoutDurationSeconds: 3_600)
        let claimDate = Date(timeIntervalSince1970: 1_800_000_000)

        tradeStore.addHabitTrade(
            habitId: habit.id,
            amount: 100,
            createdAt: claimDate,
            shouldNotifySync: false
        )

        #expect(HabitLockout.isLocked(habit: habit, tradeStore: tradeStore, now: claimDate.addingTimeInterval(3_601)) == false)
    }

    // Behaviour: Deleted claim history should stop locking the habit so the row
    // does not stay disabled after a reverted claim.
    @Test func deletedTradesDoNotKeepHabitLocked() {
        let tradeStore = makeStore()
        let habit = makeHabit(lockoutDurationSeconds: 3_600)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        tradeStore.addHabitTrade(
            habitId: habit.id,
            amount: 100,
            createdAt: now.addingTimeInterval(-600),
            deletedAt: now.addingTimeInterval(-300),
            shouldNotifySync: false
        )

        #expect(HabitLockout.isLocked(habit: habit, tradeStore: tradeStore, now: now) == false)
    }
}
