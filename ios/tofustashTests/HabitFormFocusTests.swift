import Foundation
import Testing
@testable import tofustash

struct HabitFormFocusTests {

    // MARK: - isNameDescription

    // HabitFormFocus has a computed property `isNameDescription` that returns true
    // for both .name and .description cases — they both open the same
    // name/description editor, just focusing different fields.

    @Test func nameIsNameDescription() {
        #expect(HabitFormFocus.name.isNameDescription == true)
    }

    @Test func frequencyIsNotNameDescription() {
        #expect(HabitFormFocus.frequency.isNameDescription == false)
    }

    // MARK: - hasContent

    @Test func emptyFormHasNoContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "", frequency: nil, difficultyRank: nil, tagCount: 0
        ) == false)
    }

    @Test func nameOnlyHasContent() {
        #expect(HabitFormView.hasContent(
            name: "Run", description: "", frequency: nil, difficultyRank: nil, tagCount: 0
        ) == true)
    }

    @Test func descriptionOnlyHasContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "Some desc", frequency: nil, difficultyRank: nil, tagCount: 0
        ) == true)
    }

    @Test func frequencyOnlyHasContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "", frequency: 7.0, difficultyRank: nil, tagCount: 0
        ) == true)
    }

    @Test func difficultyOnlyHasContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "", frequency: nil, difficultyRank: "easy", tagCount: 0
        ) == true)
    }

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

    @Test func nameForAutoSaveReturnsTrimmedName() {
        #expect(HabitFormView.nameForAutoSave("  Exercise  ") == "Exercise")
    }

    @Test func nameForAutoSaveReturnsEmptyForWhitespaceOnly() {
        // Empty/whitespace name is still passed — updateHabit knows to keep existing
        #expect(HabitFormView.nameForAutoSave("   ") == "")
    }

    // MARK: - shouldUseLargeDetent

    // Determines whether the name/description editor sheet should auto-expand
    // to full-screen (.large). Short/empty content stays in a compact detent
    // so the HabitList remains visible underneath. When the user types enough
    // content, the sheet expands to give them room.

    @Test func emptyContentShouldNotUseLargeDetent() {
        #expect(HabitFormView.shouldUseLargeDetent(name: "", description: "") == false)
    }

    @Test func shortContentShouldNotUseLargeDetent() {
        #expect(HabitFormView.shouldUseLargeDetent(name: "Run", description: "Quick jog") == false)
    }

    @Test func longDescriptionShouldUseLargeDetent() {
        let longDesc = String(repeating: "a", count: 101)
        #expect(HabitFormView.shouldUseLargeDetent(name: "", description: longDesc) == true)
    }

    @Test func longNameShouldUseLargeDetent() {
        let longName = String(repeating: "a", count: 101)
        #expect(HabitFormView.shouldUseLargeDetent(name: longName, description: "") == true)
    }

    @Test func combinedLengthShouldUseLargeDetent() {
        // Each alone is under 100, but combined they exceed it
        let name = String(repeating: "a", count: 60)
        let desc = String(repeating: "b", count: 50)
        #expect(HabitFormView.shouldUseLargeDetent(name: name, description: desc) == true)
    }

    @Test func multilineDescriptionShouldUseLargeDetent() {
        // 4+ lines (3+ newlines) should trigger large even if total chars < 100
        let desc = "Line 1\nLine 2\nLine 3\nLine 4"
        #expect(HabitFormView.shouldUseLargeDetent(name: "", description: desc) == true)
    }

    @Test func threeLineDescriptionShouldNotUseLargeDetent() {
        // 3 lines (2 newlines) fits in the compact sheet
        let desc = "Line 1\nLine 2\nLine 3"
        #expect(HabitFormView.shouldUseLargeDetent(name: "", description: desc) == false)
    }

    // MARK: - buildPillData

    // buildPillData is a static/pure function that returns the data for the pill
    // row (Tags, Difficulty, Frequency). This lets us test the logic without
    // needing to instantiate a full SwiftUI view.
    //
    // Key behavior: the Tags pill should ALWAYS appear in the list, regardless
    // of whether tags are applied. When tags are applied, its `isSet` flag
    // should be true (renders orange), matching the frequency/difficulty pattern.

    @Test func tagsPillAlwaysPresent_noTags() {
        let pills = HabitFormView.buildPillData(
            hasTagsApplied: false,
            difficultyRank: nil,
            frequency: nil
        )
        // Tags pill should exist even when no tags are applied
        let tagsPill = pills.first { $0.id == "tags" }
        #expect(tagsPill != nil)
        #expect(tagsPill?.isSet == false)
        #expect(tagsPill?.label == "Tags")
    }

    @Test func tagsPillAlwaysPresent_withTags() {
        let pills = HabitFormView.buildPillData(
            hasTagsApplied: true,
            difficultyRank: nil,
            frequency: nil
        )
        // Tags pill should still exist when tags are applied, but highlighted orange
        let tagsPill = pills.first { $0.id == "tags" }
        #expect(tagsPill != nil)
        #expect(tagsPill?.isSet == true)
        #expect(tagsPill?.label == "Tags")
    }

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

    @Test func difficultyPillIsSetWhenRanked() {
        let pills = HabitFormView.buildPillData(
            hasTagsApplied: false,
            difficultyRank: "hard",
            frequency: nil
        )
        let diffPill = pills.first { $0.id == "difficulty" }
        #expect(diffPill?.isSet == true)
    }

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
