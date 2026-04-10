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
}
