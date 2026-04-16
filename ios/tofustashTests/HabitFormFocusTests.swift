import Foundation
import Testing
@testable import tofustash

struct HabitFormFocusTests {

    // Behaviour: A dismissed new-habit sheet only offers recovery when the
    // user actually entered something into the form.
    @Test func emptyFormHasNoContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "", frequency: nil, difficultyRank: nil, tagCount: 0
        ) == false)
    }

    // Behaviour: Typing only a name still counts as meaningful draft content.
    @Test func nameOnlyHasContent() {
        #expect(HabitFormView.hasContent(
            name: "Run", description: "", frequency: nil, difficultyRank: nil, tagCount: 0
        ) == true)
    }

    // Behaviour: Typing only a description still counts as meaningful draft content.
    @Test func descriptionOnlyHasContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "Some desc", frequency: nil, difficultyRank: nil, tagCount: 0
        ) == true)
    }

    // Behaviour: The first habit's auto-assigned difficulty should not by itself
    // trigger the discard-recovery flow.
    @Test func autoSetDifficultyAloneHasNoContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "", frequency: nil, difficultyRank: "m",
            tagCount: 0, isFirstHabit: true
        ) == false)
    }

    // Behaviour: Name auto-save trims whitespace before sending the value to the store.
    @Test func nameForAutoSaveReturnsTrimmedName() {
        #expect(HabitFormView.nameForAutoSave("  Exercise  ") == "Exercise")
    }

    // Behaviour: A whitespace-only name is passed as empty so the store can keep
    // the existing name while still saving the other fields.
    @Test func nameForAutoSaveReturnsEmptyForWhitespaceOnly() {
        #expect(HabitFormView.nameForAutoSave("   ") == "")
    }

    // Behaviour: The Tags pill is always present so the user can discover tag editing
    // even before any tags have been applied.
    @Test func tagsPillAlwaysPresent() {
        let pills = HabitFormView.buildPillData(
            hasTagsApplied: false,
            difficultyRank: nil,
            frequency: nil
        )

        #expect(pills.count == 3)
        #expect(pills[0].id == "tags")
        #expect(pills[0].label == "Tags")
    }

    // Behaviour: When frequency is set, the frequency pill shows a formatted summary
    // rather than the default placeholder label.
    @Test func frequencyPillShowsSummaryWhenSet() {
        let pills = HabitFormView.buildPillData(
            hasTagsApplied: false,
            difficultyRank: nil,
            frequency: 1.0
        )

        #expect(pills[2].isSet == true)
        #expect(pills[2].label != "Frequency")
    }

    // Behaviour: The very first habit gets the midpoint difficulty rank.
    @Test func defaultDifficultyRankForFirstHabitReturnsMidpointKey() {
        #expect(HabitFormView.defaultDifficultyRankForFirstHabit() == "m")
    }

    // Behaviour: When there are no ranked comparison habits, tapping the difficulty
    // pill should not open the ranker.
    @Test func shouldOpenDifficultyRankerReturnsFalseWithoutComparableHabits() {
        #expect(HabitFormView.shouldOpenDifficultyRanker(
            isFirstHabit: false,
            hasComparableHabits: false
        ) == false)
    }

    // Behaviour: When comparison habits exist, tapping difficulty opens the ranker.
    @Test func shouldOpenDifficultyRankerReturnsTrueWithComparableHabits() {
        #expect(HabitFormView.shouldOpenDifficultyRanker(
            isFirstHabit: false,
            hasComparableHabits: true
        ) == true)
    }
}
