import Testing
@testable import tofustash

struct HabitFormFocusTests {
    // Behaviour: Closing a brand-new habit form should only offer recovery when
    // the user actually entered something meaningful.
    @Test func blankDraftHasNoRecoverableContent() {
        #expect(HabitFormView.hasContent(
            name: "",
            description: "",
            frequency: nil,
            difficultyTier: nil,
            tagCount: 0
        ) == false)
    }

    // Behaviour: Auto-filled defaults for the very first habit should not count
    // as intentional user input by themselves.
    @Test func firstHabitDifficultyAloneDoesNotCountAsDraftContent() {
        #expect(HabitFormView.hasContent(
            name: "",
            description: "",
            frequency: nil,
            difficultyTier: .medium,
            tagCount: 0,
            isFirstHabit: true
        ) == false)
    }

    // Behaviour: The difficulty pill shows the selected tier so the user can
    // confirm what they picked without reopening the modal.
    @Test func difficultyPillUsesTierDisplayName() {
        let pills = HabitFormView.buildPillData(
            hasTagsApplied: false,
            difficultyTier: .hard,
            frequency: 1.0
        )

        #expect(pills.count == 3)
        #expect(pills[1].id == "difficulty")
        #expect(pills[1].label == "Hard")
        #expect(pills[1].isSet == true)
    }

    // Behaviour: Frequency pills switch from the placeholder copy to a summary
    // once the user sets a target.
    @Test func frequencyPillShowsSummaryWhenSet() {
        let pills = HabitFormView.buildPillData(
            hasTagsApplied: false,
            difficultyTier: nil,
            frequency: 1.0
        )

        #expect(pills[2].id == "frequency")
        #expect(pills[2].isSet == true)
        #expect(pills[2].label != "Frequency")
    }

    // Behaviour: Auto-save trims accidental whitespace before the store sees
    // the habit name.
    @Test func autoSaveNameIsTrimmed() {
        #expect(HabitFormView.nameForAutoSave("  Exercise  ") == "Exercise")
    }
}
