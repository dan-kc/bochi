import Foundation
import Testing
@testable import tofustash

struct HabitFormFocusTests {

    // MARK: - isNameDescription

    // HabitFormFocus has a computed property `isNameDescription` that returns true
    // for both .name and .description cases — they both open the same
    // name/description editor, just focusing different fields.

    // Behaviour: When the user taps the name field, the name/description editor opens.
    @Test func nameIsNameDescription() {
        #expect(HabitFormFocus.name.isNameDescription == true)
    }

    // Behaviour: When the user taps frequency, it does NOT open the name/description
    // editor — it opens the frequency picker instead.
    @Test func frequencyIsNotNameDescription() {
        #expect(HabitFormFocus.frequency.isNameDescription == false)
    }

    // MARK: - hasContent

    // Behaviour: The discard confirmation dialog only appears when the form has content.
    // An empty form (no name, description, frequency, difficulty, or tags) is considered
    // content-free and can be dismissed without warning.

    @Test func emptyFormHasNoContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "", frequency: nil, difficultyRank: nil, tagCount: 0
        ) == false)
    }

    // Behaviour: A form with just a name typed in is considered to have content.
    @Test func nameOnlyHasContent() {
        #expect(HabitFormView.hasContent(
            name: "Run", description: "", frequency: nil, difficultyRank: nil, tagCount: 0
        ) == true)
    }

    // Behaviour: A form with just a description typed in is considered to have content.
    @Test func descriptionOnlyHasContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "Some desc", frequency: nil, difficultyRank: nil, tagCount: 0
        ) == true)
    }

    // Behaviour: A form with only a frequency set is considered to have content.
    @Test func frequencyOnlyHasContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "", frequency: 7.0, difficultyRank: nil, tagCount: 0
        ) == true)
    }

    // Behaviour: A form with only a difficulty rank set is considered to have content.
    @Test func difficultyOnlyHasContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "", frequency: nil, difficultyRank: "easy", tagCount: 0
        ) == true)
    }

    // Behaviour: A form with only tags applied is considered to have content.
    @Test func tagsOnlyHasContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "", frequency: nil, difficultyRank: nil, tagCount: 2
        ) == true)
    }

    // MARK: - nameForAutoSave

    // In change mode, the form auto-saves on every field change. The name field
    // needs special handling: we always pass it to updateHabit so it stays in sync,
    // but if it's temporarily invalid (empty while typing), updateHabit will
    // gracefully keep the existing name. This helper returns the name to pass.

    // Behaviour: When auto-saving, the habit name is trimmed of whitespace.
    @Test func nameForAutoSaveReturnsTrimmedName() {
        #expect(HabitFormView.nameForAutoSave("  Exercise  ") == "Exercise")
    }

    // Behaviour: When auto-saving while the name field is temporarily blank (user
    // is mid-edit), an empty string is passed so updateHabit knows to keep the existing name.
    @Test func nameForAutoSaveReturnsEmptyForWhitespaceOnly() {
        #expect(HabitFormView.nameForAutoSave("   ") == "")
    }

    // MARK: - buildPillData

    // buildPillData is a static/pure function that returns the data for the pill
    // row (Tags, Difficulty, Frequency). This lets us test the logic without
    // needing to instantiate a full SwiftUI view.

    // Behaviour: The Tags pill always appears in the form even when no tags are applied,
    // so the user can discover and tap it to add tags.
    @Test func tagsPillAlwaysPresent_noTags() {
        let pills = HabitFormView.buildPillData(
            hasTagsApplied: false,
            difficultyRank: nil,
            frequency: nil
        )
        let tagsPill = pills.first { $0.id == "tags" }
        #expect(tagsPill != nil)
        #expect(tagsPill?.isSet == false)
        #expect(tagsPill?.label == "Tags")
    }

    // Behaviour: When tags are applied, the Tags pill is highlighted (isSet = true)
    // so the user can see at a glance that tags are configured.
    @Test func tagsPillAlwaysPresent_withTags() {
        let pills = HabitFormView.buildPillData(
            hasTagsApplied: true,
            difficultyRank: nil,
            frequency: nil
        )
        let tagsPill = pills.first { $0.id == "tags" }
        #expect(tagsPill != nil)
        #expect(tagsPill?.isSet == true)
        #expect(tagsPill?.label == "Tags")
    }

    // Behaviour: The pills always appear in a consistent order (Tags, Difficulty,
    // Frequency) so the user builds muscle memory for tapping them.
    @Test func pillOrderIsTagsDifficultyFrequency() {
        let pills = HabitFormView.buildPillData(
            hasTagsApplied: false,
            difficultyRank: nil,
            frequency: nil
        )
        #expect(pills.count == 3)
        #expect(pills[0].id == "tags")
        #expect(pills[1].id == "difficulty")
        #expect(pills[2].id == "frequency")
    }

    // Behaviour: When a difficulty rank is set, the Difficulty pill is highlighted
    // so the user sees it's been configured.
    @Test func difficultyPillIsSetWhenRanked() {
        let pills = HabitFormView.buildPillData(
            hasTagsApplied: false,
            difficultyRank: "hard",
            frequency: nil
        )
        let diffPill = pills.first { $0.id == "difficulty" }
        #expect(diffPill?.isSet == true)
    }

    // Behaviour: When frequency is set, the Frequency pill shows the formatted summary
    // (e.g. "3/week") instead of the generic "Frequency" label.
    @Test func frequencyPillShowsSummaryWhenSet() {
        let pills = HabitFormView.buildPillData(
            hasTagsApplied: false,
            difficultyRank: nil,
            frequency: 1.0  // 1/day
        )
        let freqPill = pills.first { $0.id == "frequency" }
        #expect(freqPill?.isSet == true)
        // Should show the formatted summary, not "Frequency"
        #expect(freqPill?.label != "Frequency")
    }

    // Behaviour: When no frequency is set, the Frequency pill shows the default
    // "Frequency" label so the user knows what it's for.
    @Test func frequencyPillShowsDefaultLabelWhenUnset() {
        let pills = HabitFormView.buildPillData(
            hasTagsApplied: false,
            difficultyRank: nil,
            frequency: nil
        )
        let freqPill = pills.first { $0.id == "frequency" }
        #expect(freqPill?.isSet == false)
        #expect(freqPill?.label == "Frequency")
    }
}
