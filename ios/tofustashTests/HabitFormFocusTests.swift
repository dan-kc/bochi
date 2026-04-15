import Foundation
import Testing
@testable import tofustash

struct HabitFormFocusTests {

    // MARK: - Initial flow surface

    // Behaviour: Tapping "+" to create a habit should open directly into the
    // name/description editor, so the user does not see the full habit form yet.
    @Test func newHabitStartsOnNameDescriptionSurface() {
        #expect(HabitFormView.initialSurface(
            mode: .new,
            initialFocus: nil,
            hasPrefill: false
        ) == .nameDescription)
    }

    // Behaviour: Recovering a discarded draft should re-open on the full form,
    // because the user already went past the name/description step before.
    @Test func recoveredDraftStartsOnMainFormSurface() {
        #expect(HabitFormView.initialSurface(
            mode: .new,
            initialFocus: nil,
            hasPrefill: true
        ) == .form)
    }

    // Behaviour: Editing an existing habit normally starts on the full form.
    @Test func editHabitStartsOnMainFormSurface() {
        let habit = Habit(
            id: "1", name: "Test", description: "",
            createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            frequency: nil, difficultyRank: nil
        )

        #expect(HabitFormView.initialSurface(
            mode: .change(habit),
            initialFocus: nil,
            hasPrefill: false
        ) == .form)
    }

    // Behaviour: If the user specifically tapped the description row, editing
    // should jump straight into the name/description editor again.
    @Test func tappedDescriptionStartsOnNameDescriptionSurface() {
        let habit = Habit(
            id: "1", name: "Test", description: "",
            createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            frequency: nil, difficultyRank: nil
        )

        #expect(HabitFormView.initialSurface(
            mode: .change(habit),
            initialFocus: .description,
            hasPrefill: false
        ) == .nameDescription)
    }

    // Behaviour: When the user enters through the description affordance, the
    // description field should receive focus instead of the name field.
    @Test func descriptionEntryPrefersDescriptionFocus() {
        #expect(HabitFormView.initialEntryFocus(initialFocus: .description) == .description)
    }

    // Behaviour: All other entry paths default keyboard focus to the name field.
    @Test func defaultEntryPrefersNameFocus() {
        #expect(HabitFormView.initialEntryFocus(initialFocus: nil) == .name)
        #expect(HabitFormView.initialEntryFocus(initialFocus: .name) == .name)
    }

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

    // Behaviour: A recovery toast only appears when the dismissed form had content.
    // An empty form (no name, description, frequency, difficulty, or tags) is considered
    // content-free and can be dismissed without showing a toast.

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

    // Behaviour: When difficulty is auto-set for the first habit (no other habits exist),
    // the form should NOT be considered to have content — the user didn't actively enter
    // anything, so dismissing shouldn't trigger a recovery toast.
    @Test func autoSetDifficultyAloneHasNoContent() {
        #expect(HabitFormView.hasContent(
            name: "", description: "", frequency: nil, difficultyRank: "m",
            tagCount: 0, isFirstHabit: true
        ) == false)
    }

    // Behaviour: When the first habit has user-entered content beyond the auto-set
    // difficulty (e.g. a name), it should still count as having content.
    @Test func firstHabitWithNameHasContent() {
        #expect(HabitFormView.hasContent(
            name: "Run", description: "", frequency: nil, difficultyRank: "m",
            tagCount: 0, isFirstHabit: true
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

    // MARK: - First habit detection

    // Behaviour: When the user creates their very first habit (no active habits exist),
    // difficulty is pre-set automatically since there's nothing to compare against.
    @Test func isFirstHabit_newModeNoActiveHabits_returnsTrue() {
        #expect(HabitFormView.isFirstHabit(mode: .new, activeHabitsCount: 0) == true)
    }

    // Behaviour: When active habits already exist, the user must go through the
    // difficulty ranker to compare against them.
    @Test func isFirstHabit_newModeWithActiveHabits_returnsFalse() {
        #expect(HabitFormView.isFirstHabit(mode: .new, activeHabitsCount: 3) == false)
    }

    // Behaviour: When editing an existing habit, it's never treated as "first habit"
    // even if it's the only one — the habit already exists.
    @Test func isFirstHabit_changeMode_returnsFalse() {
        let habit = Habit(
            id: "1", name: "Test", description: "",
            createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            frequency: nil, difficultyRank: nil
        )
        #expect(HabitFormView.isFirstHabit(mode: .change(habit), activeHabitsCount: 1) == false)
    }

    // Behaviour: The default difficulty rank for the first habit is the midpoint key,
    // leaving room for future habits above and below.
    @Test func defaultDifficultyRankForFirstHabit_returnsMidpointKey() {
        #expect(HabitFormView.defaultDifficultyRankForFirstHabit() == "m")
    }

    // MARK: - Comparable habits detection

    // Behaviour: When creating the first habit, there are no other ranked habits
    // to compare against, so the ranker should not open.
    @Test func hasComparableHabits_newModeNoHabits_returnsFalse() {
        #expect(HabitFormView.hasComparableHabits(
            rankedHabitCount: 0, excludeHabitId: nil
        ) == false)
    }

    // Behaviour: When editing the only habit (which is ranked), after excluding
    // itself there are no other ranked habits to compare against.
    @Test func hasComparableHabits_changeModeSingleHabit_returnsFalse() {
        // 1 ranked habit exists, but it's the one being edited (excluded)
        #expect(HabitFormView.hasComparableHabits(
            rankedHabitCount: 0, excludeHabitId: "habit-1"
        ) == false)
    }

    // Behaviour: When other ranked habits exist to compare against, the ranker
    // should open so the user can rank their habit via binary search.
    @Test func hasComparableHabits_multipleHabits_returnsTrue() {
        #expect(HabitFormView.hasComparableHabits(
            rankedHabitCount: 2, excludeHabitId: "habit-1"
        ) == true)
    }

    // MARK: - Difficulty pill tap behavior

    // Behaviour: For the first habit, tapping the difficulty pill should not open
    // the ranker since difficulty is already auto-set.
    @Test func shouldOpenDifficultyRanker_firstHabit_returnsFalse() {
        #expect(HabitFormView.shouldOpenDifficultyRanker(isFirstHabit: true, hasComparableHabits: false) == false)
    }

    // Behaviour: For subsequent habits, tapping the difficulty pill opens the ranker
    // so the user can compare against existing habits.
    @Test func shouldOpenDifficultyRanker_notFirstHabit_returnsTrue() {
        #expect(HabitFormView.shouldOpenDifficultyRanker(isFirstHabit: false, hasComparableHabits: true) == true)
    }

    // Behaviour: When editing the only habit, tapping the difficulty pill should
    // show the alert instead of opening the ranker — there's nothing to compare against.
    @Test func shouldOpenDifficultyRanker_changeModeSingleHabit_returnsFalse() {
        #expect(HabitFormView.shouldOpenDifficultyRanker(isFirstHabit: false, hasComparableHabits: false) == false)
    }
}
