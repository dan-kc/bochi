import Foundation
import Testing
@testable import tofustash

struct ReminderQuickOptionTests {
    // Behaviour: due-date quick actions should only offer offsets that still
    // land in the future, otherwise the user would get dead one-tap choices.
    @Test func quickOptionsExcludePastOffsets() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let dueDate = now.addingTimeInterval(30 * 60)

        let options = ReminderQuickOptions.options(
            dueDate: dueDate,
            now: now
        )

        #expect(options.map(\.title) == ["15 minutes before due", "5 minutes before due"])
    }

    // Behaviour: when all offsets are valid, the task reminder modal should
    // keep the explicit shortcut order requested by product.
    @Test func quickOptionsKeepConfiguredDisplayOrder() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let dueDate = now.addingTimeInterval(2 * 60 * 60)

        let options = ReminderQuickOptions.options(
            dueDate: dueDate,
            now: now
        )

        #expect(options.map(\.title) == [
            "15 minutes before due",
            "5 minutes before due",
            "1 hour before due"
        ])
    }
}
