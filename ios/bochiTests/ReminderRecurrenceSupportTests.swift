import Foundation
import Testing
@testable import bochi

struct ReminderRecurrenceSupportTests {
    // Behaviour: recurring reminders should stay anchored to the originally
    // chosen start time so the next occurrence does not drift after each fire.
    @Test func nextOccurrenceStaysAnchoredToOriginalStartTime() {
        let startAt = Date(timeIntervalSince1970: 1_900_000_000)
        let now = startAt.addingTimeInterval((2 * 24 * 60 * 60) + (2 * 60 * 60))
        let draft = ReminderDraft(
            scheduledAt: startAt,
            recurrence: ReminderRecurrence(intervalValue: 2, unit: .days)
        )

        let nextOccurrence = ReminderDraftSupport.nextOccurrence(for: draft, now: now)

        #expect(nextOccurrence == startAt.addingTimeInterval(4 * 24 * 60 * 60))
    }

    // Behaviour: once a recurring reminder has started, it should still count
    // as active because the user expects the recurrence to remain live.
    @Test func recurringReminderRemainsActiveAfterEarlierOccurrencePasses() {
        let startAt = Date(timeIntervalSince1970: 1_900_000_000)
        let now = startAt.addingTimeInterval((24 * 60 * 60) + 60)
        let recurring = ReminderDraft(
            id: "hydration-reminder",
            scheduledAt: startAt,
            recurrence: ReminderRecurrence(intervalValue: 1, unit: .days)
        )

        #expect(ReminderDraftSupport.active([recurring], now: now).map(\.id) == ["hydration-reminder"])
    }

    // Behaviour: weekly recurrence input should stop at fifty-two weeks so the
    // repeat control stays within the requested product bounds.
    @Test func weeklyRecurrenceRejectsIntervalsAboveFiftyTwoWeeks() {
        #expect(ReminderRecurrence(intervalValue: 52, unit: .weeks).isValid == true)
        #expect(ReminderRecurrence(intervalValue: 53, unit: .weeks).isValid == false)
    }
}
