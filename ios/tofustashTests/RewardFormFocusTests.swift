import Testing
@testable import tofustash

struct RewardFormFocusTests {
    // Behaviour: Closing a blank new-reward form should not offer a recovery toast.
    @Test func emptyFormHasNoContent() {
        #expect(RewardFormView.hasContent(
            name: "", description: "", maxFrequency: nil, damageRank: nil, tagCount: 0
        ) == false)
    }

    // Behaviour: Typing only a reward name still counts as a meaningful draft.
    @Test func nameOnlyHasContent() {
        #expect(RewardFormView.hasContent(
            name: "Ice Cream", description: "", maxFrequency: nil, damageRank: nil, tagCount: 0
        ) == true)
    }

    // Behaviour: The first reward's auto-assigned midpoint damage should not by itself count as user-entered draft content.
    @Test func autoSetDamageAloneHasNoContentForFirstReward() {
        #expect(RewardFormView.hasContent(
            name: "", description: "", maxFrequency: nil, damageRank: "m", tagCount: 0, isFirstReward: true
        ) == false)
    }

    // Behaviour: Name auto-save trims whitespace before the reward store sees it.
    @Test func nameForAutoSaveTrimsWhitespace() {
        #expect(RewardFormView.nameForAutoSave("  Chips  ") == "Chips")
    }

    // Behaviour: When max frequency is set, the frequency pill shows a summary instead of the placeholder label.
    @Test func frequencyPillShowsSummaryWhenSet() {
        let pills = RewardFormView.buildPillData(
            hasTagsApplied: false,
            damageRank: nil,
            maxFrequency: 1.0
        )

        #expect(pills[2].isSet == true)
        #expect(pills[2].label != "Max Frequency")
    }

    // Behaviour: When there are no ranked comparison rewards, tapping damage
    // should initialize a default rank instead of showing an error.
    @Test func damageSelectionAssignsDefaultRankWithoutComparableRewards() {
        #expect(RewardFormView.damageRankAfterSelection(
            currentDamageRank: nil,
            hasComparableRewards: false
        ) == "m")
    }

    // Behaviour: Existing damage stays intact when no comparisons remain.
    @Test func damageSelectionPreservesExistingRankWithoutComparableRewards() {
        #expect(RewardFormView.damageRankAfterSelection(
            currentDamageRank: "a0",
            hasComparableRewards: false
        ) == "a0")
    }

    // Behaviour: A ranked peer still means the damage ranker should open.
    @Test func shouldOpenDamageRankerReturnsTrueWithComparableRewards() {
        #expect(RewardFormView.shouldOpenDamageRanker(
            hasComparableRewards: true
        ) == true)
    }
}
