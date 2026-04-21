import Testing
@testable import tofustash

struct RewardFormFocusTests {
    // Behaviour: Closing a blank reward form should not offer draft recovery.
    @Test func blankDraftHasNoRecoverableContent() {
        #expect(RewardFormView.hasContent(
            name: "",
            description: "",
            maxFrequency: nil,
            damageTier: nil,
            tagCount: 0
        ) == false)
    }

    // Behaviour: Auto-filled defaults for the first reward should not count as
    // user-authored content on their own.
    @Test func firstRewardDamageAloneDoesNotCountAsDraftContent() {
        #expect(RewardFormView.hasContent(
            name: "",
            description: "",
            maxFrequency: nil,
            damageTier: .medium,
            tagCount: 0,
            isFirstReward: true
        ) == false)
    }

    // Behaviour: The damage pill shows the selected tier label directly in the
    // form so the user can review it at a glance.
    @Test func damagePillUsesTierDisplayName() {
        let pills = RewardFormView.buildPillData(
            hasTagsApplied: false,
            damageTier: .heavy,
            maxFrequency: 1.0
        )

        #expect(pills.count == 3)
        #expect(pills[1].id == "damage")
        #expect(pills[1].label == "Heavy")
        #expect(pills[1].isSet == true)
    }

    // Behaviour: Max frequency pills show a human-readable summary after the
    // user sets the cap.
    @Test func frequencyPillShowsSummaryWhenSet() {
        let pills = RewardFormView.buildPillData(
            hasTagsApplied: false,
            damageTier: nil,
            maxFrequency: 1.0
        )

        #expect(pills[2].id == "frequency")
        #expect(pills[2].isSet == true)
        #expect(pills[2].label != "Max Frequency")
    }

    // Behaviour: Auto-save trims accidental whitespace from reward names.
    @Test func autoSaveNameIsTrimmed() {
        #expect(RewardFormView.nameForAutoSave("  Chips  ") == "Chips")
    }

    // Behaviour: Reward forms should still show pricing placeholders even when
    // buying is no longer blocked by missing pricing fields.
    @Test func blankRewardPillsStillShowPlaceholders() {
        let pills = RewardFormView.buildPillData(
            hasTagsApplied: false,
            damageTier: nil,
            maxFrequency: nil
        )

        #expect(pills[1].label == "Damage")
        #expect(pills[2].label == "Max Frequency")
    }
}
