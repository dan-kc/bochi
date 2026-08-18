import Foundation
import Testing
@testable import bochi

struct EntityFormSupportTests {
    // Behaviour: when a user only types whitespace around a name, auto-save
    // should persist the intentional name instead of preserving the padding.
    @Test func trimmedNameRemovesOuterWhitespace() {
        #expect(EntityFormSupport.trimmedName("  Read  ") == "Read")
    }

    // Behaviour: dismissing a brand-new draft should only offer recovery after
    // the user entered something meaningful into the form.
    @Test func recoverableContentIgnoresBlankDraft() {
        #expect(EntityFormSupport.hasRecoverableContent(
            name: "",
            description: "",
            primaryValueIsSet: false,
            secondaryValueIsSet: false,
            tagCount: 0
        ) == false)
    }

    // Behaviour: first-run defaults should not create a fake discard prompt
    // before the user actually changes anything.
    @Test func recoverableContentCanIgnoreAutofilledSecondaryField() {
        #expect(EntityFormSupport.hasRecoverableContent(
            name: "",
            description: "",
            primaryValueIsSet: false,
            secondaryValueIsSet: true,
            tagCount: 0,
            ignoreSecondaryValue: true
        ) == false)
    }

    // Behaviour: pill-building should preserve the configured label, icon, and
    // action state without adding extra presentation-only metadata.
    @Test func buildPillsPreservesConfiguredPillState() {
        let pills = EntityFormSupport.buildPills(
            configs: [
                EntityFormPillConfig(id: "tags", label: "Tags", icon: "tag", isSet: true),
                EntityFormPillConfig(id: "frequency", label: "Frequency", icon: "clock", isSet: false),
            ],
            actions: [:]
        )

        #expect(pills[0].id == "tags")
        #expect(pills[0].label == "Tags")
        #expect(pills[0].icon == "tag")
        #expect(pills[0].isSet == true)
        #expect(pills[1].id == "frequency")
        #expect(pills[1].label == "Frequency")
        #expect(pills[1].icon == "clock")
        #expect(pills[1].isSet == false)
    }

    // Behaviour: when premium lapses, only saved premium-only settings should
    // explain that they will return after renewal.
    @Test func premiumRenewalNoticesDescribeOnlySetLockedPills() {
        let notices = EntityFormSupport.premiumRenewalNotices(for: [
            PillItem(id: "reminders", label: "2 reminders", icon: "bell", isSet: true, isPremiumLocked: true),
            PillItem(id: "lockout", label: "1h", icon: "lock", isSet: true, isPremiumLocked: true),
            PillItem(id: "dependencies", label: "Dependencies", icon: "lock.doc", isSet: true, isPremiumLocked: true),
            PillItem(id: "timer", label: "Tabata", icon: "stopwatch", isSet: true, isPremiumLocked: true),
            PillItem(id: "frequency", label: "Frequency", icon: "clock", isSet: false, isPremiumLocked: true),
        ])

        #expect(notices == [
            "Your existing reminders will return on premium renewal.",
            "Your existing lockout will return on premium renewal.",
            "Your existing dependencies will return on premium renewal.",
            "Your existing timer will return on premium renewal.",
        ])
    }

    // Behaviour: clearing price in an edit modal should not overwrite the
    // persisted price because edit forms require a saved price.
    @Test func editPriceModalRejectsBlankPrice() {
        let result = BasePriceModalSupport.saveResult(
            text: "   ",
            currentPrice: 200,
            allowsUnsetPrice: false
        )

        if case .missingRequiredPrice = result {
            #expect(true)
        } else {
            Issue.record("Expected blank edit price to be rejected.")
        }
    }

    // Behaviour: clearing price in the new form's modal may save an unset
    // draft because the parent new form owns the required-field feedback.
    @Test func newFormPriceModalAllowsBlankDraftPrice() {
        let result = BasePriceModalSupport.saveResult(
            text: "",
            currentPrice: nil,
            allowsUnsetPrice: true
        )

        if case .valid(nil) = result {
            #expect(true)
        } else {
            Issue.record("Expected blank new-form draft price to remain unset.")
        }
    }

    // Behaviour: typed prices must stay inside the backend integer contract so
    // a locally saved price can always sync to Postgres.
    @Test func priceModalClampsTypedPriceToBackendMaximum() {
        let result = BasePriceModalSupport.saveResult(
            text: String(BackendIntegerContract.max),
            currentPrice: nil,
            allowsUnsetPrice: false
        )

        if case .valid(let price) = result {
            #expect(price == BackendIntegerContract.max)
        } else {
            Issue.record("Expected the maximum backend price to be accepted.")
        }

        let overflowingResult = BasePriceModalSupport.saveResult(
            text: String(BackendIntegerContract.max + 1),
            currentPrice: nil,
            allowsUnsetPrice: false
        )

        if case .valid(let price) = overflowingResult {
            #expect(price == BackendIntegerContract.max)
        } else {
            Issue.record("Expected an oversized price to clamp to the backend maximum.")
        }

        let unparseablyLargeResult = BasePriceModalSupport.saveResult(
            text: "999999999999999999999999999999999999",
            currentPrice: 200,
            allowsUnsetPrice: false
        )

        if case .valid(let price) = unparseablyLargeResult {
            #expect(price == BackendIntegerContract.max)
        } else {
            Issue.record("Expected a very large pasted price to clamp to the backend maximum.")
        }
    }

    // Behaviour: task forms should put the submitted price on the first row.
    @Test func taskFormPricePillsMatchListRowOrder() {
        let pills = TaskFormView.buildPricePillData(basePrice: 200)

        #expect(pills.map { $0.id } == ["price"])
        #expect(pills.map { $0.label } == ["200"])
    }

    // Behaviour: a brand-new task with no submitted price should show a price
    // placeholder instead of looking like a zero- or default-priced task.
    @Test func unsetTaskPricePillShowsPlaceholder() {
        let pills = TaskFormView.buildPricePillData(basePrice: nil)

        #expect(pills.map { $0.label } == ["Price"])
        #expect(pills[0].isSet == false)
    }

    // Behaviour: task form controls that do not affect price should stay on a
    // separate row, with timer immediately after tags for fast access.
    @Test func taskFormNonPricePillsAreSeparateFromPricePills() {
        let dueDate = Date(timeIntervalSince1970: 1_800_086_400)

        let pills = TaskFormView.buildNonPricePillData(
            hasTagsApplied: true,
            dueDate: dueDate,
            reminderSummary: "2 reminders",
            hasReminders: true,
            dependencyCount: 2
        )

        #expect(pills.map { $0.id } == ["tags", "timer", "dueDate", "reminders", "dependencies"])
        #expect(pills[0].label == "Tags")
        #expect(pills[1].label == "Timer")
        #expect(pills[2].isSet == true)
        #expect(pills[3].label == "2 reminders")
        #expect(pills[4].label == "Dependencies")
        #expect(pills[4].isSet == true)
    }

    // Behaviour: recurringTask forms show submitted base price followed by minimum
    // frequency on the price row.
    @Test func recurringTaskFormPricePillsMatchListRowOrder() {
        let pills = RecurringTaskFormView.buildPricePillData(
            basePrice: 125,
            frequency: 1.0 / 7.0
        )

        #expect(pills.map { $0.id } == ["price", "frequency"])
        #expect(pills.map { $0.label } == ["125", "Min 1/week"])
    }

    // Behaviour: a brand-new recurring task with no submitted base price should
    // ask for Base Price before the user can add it.
    @Test func unsetRecurringTaskBasePricePillShowsPlaceholder() {
        let pills = RecurringTaskFormView.buildPricePillData(
            basePrice: nil,
            frequency: nil
        )

        #expect(pills.map { $0.label } == ["Base Price", "Min Frequency"])
        #expect(pills[0].isSet == false)
    }

    // Behaviour: recurringTask form controls that do not affect price should stay on a
    // separate row, with timer immediately after tags for fast access.
    @Test func recurringTaskFormNonPricePillsAreSeparateFromPricePills() {
        let pills = RecurringTaskFormView.buildNonPricePillData(
            hasTagsApplied: true,
            lockoutDurationSeconds: 3_600,
            reminderSummary: "2 reminders",
            hasReminders: true
        )

        #expect(pills.map { $0.id } == ["tags", "timer", "reminders", "lockout"])
        #expect(pills.map { $0.label } == ["Tags", "Timer", "2 reminders", "1h"])
    }

    // Behaviour: reward forms show submitted base price followed by max
    // frequency on the price row.
    @Test func rewardFormPricePillsMatchListRowOrder() {
        let pills = RewardFormView.buildPricePillData(
            basePrice: 450,
            maxFrequency: 1.0 / 7.0
        )

        #expect(pills.map { $0.id } == ["price", "frequency"])
        #expect(pills.map { $0.label } == ["450", "Max 1/week"])
    }

    // Behaviour: a brand-new reward with no submitted base price should ask for
    // Base Price before the user can add it.
    @Test func unsetRewardBasePricePillShowsPlaceholder() {
        let pills = RewardFormView.buildPricePillData(
            basePrice: nil,
            maxFrequency: nil
        )

        #expect(pills.map { $0.label } == ["Base Price", "Max Frequency"])
        #expect(pills[0].isSet == false)
    }

    // Behaviour: reward form controls that do not affect price should stay on a
    // separate row, with timer immediately after tags for fast access.
    @Test func rewardFormNonPricePillsAreSeparateFromPricePills() {
        let pills = RewardFormView.buildNonPricePillData(
            hasTagsApplied: true,
            lockoutDurationSeconds: 3_600,
            dependencyCount: 1
        )

        #expect(pills.map { $0.id } == ["tags", "timer", "lockout", "dependencies"])
        #expect(pills.map { $0.label } == ["Tags", "Timer", "1h", "Dependencies"])
        #expect(pills[3].isSet == true)
    }
}
