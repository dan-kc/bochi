import Foundation
import Testing
@testable import tofustash

struct RecentActivitySummaryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    // Behaviour: when the last activity happened today, the editor should keep
    // the date line short and anchor it to "today" so the user can scan it fast.
    @Test("text formats same-day activity as today")
    func formatsTodayActivity() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let date = now.addingTimeInterval(-300)

        let text = RecentActivitySummary.text(
            prefix: "Last completed",
            date: date,
            now: now,
            calendar: calendar,
            timeText: { _ in "3:46 PM" },
            fullDateTimeText: { _ in "May 2 at 3:46 PM" }
        )

        #expect(text == "Last completed at 3:46 PM today")
    }

    // Behaviour: yesterday's activity should stay relative so the user can
    // quickly tell it was recent without parsing a calendar date.
    @Test("text formats previous-day activity as yesterday")
    func formatsYesterdayActivity() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let date = now.addingTimeInterval(-86_400)

        let text = RecentActivitySummary.text(
            prefix: "Last purchased",
            date: date,
            now: now,
            calendar: calendar,
            timeText: { _ in "3:46 PM" },
            fullDateTimeText: { _ in "May 1 at 3:46 PM" }
        )

        #expect(text == "Last purchased at 3:46 PM yesterday")
    }

    // Behaviour: older activity should fall back to a full date so the user
    // still has an exact reference once "today/yesterday" stops being helpful.
    @Test("text falls back to a full date for older activity")
    func formatsOlderActivityWithFullDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let date = now.addingTimeInterval(-172_800)

        let text = RecentActivitySummary.text(
            prefix: "Last completed",
            date: date,
            now: now,
            calendar: calendar,
            timeText: { _ in "3:46 PM" },
            fullDateTimeText: { _ in "May 2 at 3:46 PM" }
        )

        #expect(text == "Last completed May 2 at 3:46 PM")
    }
}
