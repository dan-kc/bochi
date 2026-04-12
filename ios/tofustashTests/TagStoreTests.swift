import Foundation
import Testing
@testable import tofustash

@MainActor
struct TagStoreTests {

    private func makeSUT() -> TagStore {
        return TagStore()
    }

    // MARK: - Initial State

    // Behaviour: When the app first loads with no data, the tag list is empty.
    @Test func initialStoreIsEmpty() {
        let sut = makeSUT()
        #expect(sut.tags.isEmpty)
        #expect(sut.activeTags.isEmpty)
        #expect(sut.habitTags.isEmpty)
    }

    // MARK: - Adding Tags

    // Behaviour: When a user creates a new tag, it appears in their tag list.
    @Test func addTagAppendsToTags() {
        let sut = makeSUT()

        let tag = sut.addTag(name: "Health")

        #expect(sut.tags.count == 1)
        #expect(tag != nil)
        #expect(tag?.name == "Health")
    }

    // Behaviour: When a user tries to create a tag with no name (or only spaces),
    // the tag is not created.
    @Test func addTagWithEmptyNameReturnsNil() {
        let sut = makeSUT()

        let tag1 = sut.addTag(name: "")
        #expect(tag1 == nil)
        #expect(sut.tags.isEmpty)

        let tag2 = sut.addTag(name: "   ")
        #expect(tag2 == nil)
        #expect(sut.tags.isEmpty)
    }

    // Behaviour: When a user types a tag name with leading/trailing spaces,
    // the name is cleaned up automatically.
    @Test func addTagTrimsWhitespace() {
        let sut = makeSUT()

        let tag = sut.addTag(name: "  Health  ")

        #expect(tag?.name == "Health")
    }

    // Behaviour: When a user creates a tag with a specific color, that color is saved.
    @Test func addTagUsesProvidedColor() {
        let sut = makeSUT()

        let tag = sut.addTag(name: "Health", colorHex: "#FF0000")

        #expect(tag?.colorHex == "#FF0000")
    }

    // Behaviour: When a user creates a tag without choosing a color, a random
    // color is automatically assigned so all tags are visually distinct.
    @Test func addTagGeneratesRandomColorWhenNoneProvided() {
        let sut = makeSUT()

        let tag = sut.addTag(name: "Health")

        // Should have a valid hex color
        #expect(tag?.colorHex.hasPrefix("#") == true)
        #expect(tag?.colorHex.count == 7)
    }

    // MARK: - Updating Tags

    // Behaviour: When a user renames a tag, the new name is saved.
    @Test func updateTagNameChangesName() {
        let sut = makeSUT()
        let tag = sut.addTag(name: "Health")!

        sut.updateTag(id: tag.id, name: "Wellness")

        #expect(sut.tags.first?.name == "Wellness")
    }

    // Behaviour: When a user changes a tag's color, the new color is saved.
    @Test func updateTagColorChangesColor() {
        let sut = makeSUT()
        let tag = sut.addTag(name: "Health", colorHex: "#FF0000")!

        sut.updateTag(id: tag.id, colorHex: "#00FF00")

        #expect(sut.tags.first?.colorHex == "#00FF00")
    }

    // MARK: - Soft Delete Tags

    // Behaviour: When a user deletes a tag, it is soft-deleted (marked with a
    // timestamp) rather than permanently removed, allowing future sync/undo.
    @Test func deleteTagSetsDeletedAt() {
        let sut = makeSUT()
        let tag = sut.addTag(name: "Health")!

        sut.deleteTag(id: tag.id)

        #expect(sut.tags.first?.deletedAt != nil)
    }

    // Behaviour: When a user deletes a tag, it disappears from the visible tag
    // list but other tags remain.
    @Test func deletedTagExcludedFromActiveTags() {
        let sut = makeSUT()
        let tag1 = sut.addTag(name: "Health")!
        _ = sut.addTag(name: "Fitness")

        sut.deleteTag(id: tag1.id)

        #expect(sut.activeTags.count == 1)
        #expect(sut.activeTags.first?.name == "Fitness")
    }

    // MARK: - Habit-Tag Associations

    // Behaviour: When a user assigns a tag to a habit, the association is created.
    @Test func addTagToHabitCreatesHabitTag() {
        let sut = makeSUT()

        sut.addTagToHabit(tagId: "tag-1", habitId: "habit-1")

        #expect(sut.habitTags.count == 1)
        #expect(sut.habitTags.first?.tagId == "tag-1")
        #expect(sut.habitTags.first?.habitId == "habit-1")
    }

    // Behaviour: When a user taps the same tag twice on a habit (e.g. toggling),
    // only one association exists — no duplicates.
    @Test func addTagToHabitDoesNotDuplicateExisting() {
        let sut = makeSUT()

        sut.addTagToHabit(tagId: "tag-1", habitId: "habit-1")
        sut.addTagToHabit(tagId: "tag-1", habitId: "habit-1")

        // Should still be just one active association
        let active = sut.habitTags.filter { $0.deletedAt == nil }
        #expect(active.count == 1)
    }

    // Behaviour: When a user removes a tag from a habit and then re-adds it,
    // the existing association is restored (not duplicated).
    @Test func addTagToHabitRestoresSoftDeletedAssociation() {
        let sut = makeSUT()

        sut.addTagToHabit(tagId: "tag-1", habitId: "habit-1")
        sut.removeTagFromHabit(tagId: "tag-1", habitId: "habit-1")

        // Re-add should restore, not create duplicate
        sut.addTagToHabit(tagId: "tag-1", habitId: "habit-1")

        let active = sut.habitTags.filter { $0.deletedAt == nil }
        #expect(active.count == 1)
    }

    // Behaviour: When a user removes a tag from a habit, the association is
    // soft-deleted (preserving history for sync).
    @Test func removeTagFromHabitSoftDeletesHabitTag() {
        let sut = makeSUT()

        sut.addTagToHabit(tagId: "tag-1", habitId: "habit-1")
        sut.removeTagFromHabit(tagId: "tag-1", habitId: "habit-1")

        #expect(sut.habitTags.first?.deletedAt != nil)
    }

    // Behaviour: When viewing a habit's details, the user sees only the tags
    // currently assigned to that habit.
    @Test func tagsForHabitReturnsCorrectTags() {
        let sut = makeSUT()
        let tag1 = sut.addTag(name: "Health")!
        let tag2 = sut.addTag(name: "Fitness")!
        _ = sut.addTag(name: "Unrelated")

        sut.addTagToHabit(tagId: tag1.id, habitId: "habit-1")
        sut.addTagToHabit(tagId: tag2.id, habitId: "habit-1")

        let tags = sut.tagsForHabit(habitId: "habit-1")
        #expect(tags.count == 2)
        #expect(tags.contains(where: { $0.name == "Health" }))
        #expect(tags.contains(where: { $0.name == "Fitness" }))
    }

    // Behaviour: When a user removes a tag from a habit, it no longer appears
    // in that habit's tag list.
    @Test func tagsForHabitExcludesRemovedTags() {
        let sut = makeSUT()
        let tag1 = sut.addTag(name: "Health")!
        let tag2 = sut.addTag(name: "Fitness")!

        sut.addTagToHabit(tagId: tag1.id, habitId: "habit-1")
        sut.addTagToHabit(tagId: tag2.id, habitId: "habit-1")
        sut.removeTagFromHabit(tagId: tag1.id, habitId: "habit-1")

        let tags = sut.tagsForHabit(habitId: "habit-1")
        #expect(tags.count == 1)
        #expect(tags.first?.name == "Fitness")
    }

    // Behaviour: When a tag itself is deleted, it no longer appears on any habit
    // that had it assigned — even though the habit-tag association still exists.
    @Test func tagsForHabitExcludesDeletedTags() {
        let sut = makeSUT()
        let tag1 = sut.addTag(name: "Health")!

        sut.addTagToHabit(tagId: tag1.id, habitId: "habit-1")
        sut.deleteTag(id: tag1.id)

        // Tag itself is deleted — should not appear even though association exists
        let tags = sut.tagsForHabit(habitId: "habit-1")
        #expect(tags.isEmpty)
    }
}
