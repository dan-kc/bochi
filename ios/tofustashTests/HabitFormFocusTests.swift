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

    @Test func descriptionIsNameDescription() {
        #expect(HabitFormFocus.description.isNameDescription == true)
    }

    @Test func frequencyIsNotNameDescription() {
        #expect(HabitFormFocus.frequency.isNameDescription == false)
    }

    @Test func difficultyIsNotNameDescription() {
        #expect(HabitFormFocus.difficulty.isNameDescription == false)
    }

    @Test func tagsIsNotNameDescription() {
        #expect(HabitFormFocus.tags.isNameDescription == false)
    }

    // MARK: - hasContent

    @Test func emptyFormHasNoContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "", frequency: nil, difficultyRank: nil, tagCount: 0
        ) == false)
    }

    @Test func whitespaceOnlyHasNoContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "  \n\t  ", frequency: nil, difficultyRank: nil, tagCount: 0
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

    @Test func nameForAutoSaveReturnsNameAsIsWhenValid() {
        #expect(HabitFormView.nameForAutoSave("Run") == "Run")
    }

    @Test func nameForAutoSaveReturnsTooLongName() {
        // Even invalid names are passed through — updateHabit handles validation
        let longName = String(repeating: "a", count: 101)
        #expect(HabitFormView.nameForAutoSave(longName) == longName)
    }
}
