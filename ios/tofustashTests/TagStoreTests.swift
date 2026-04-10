import Foundation
import Testing
@testable import tofustash

@MainActor
struct TagStoreTests {

    private func makeSUT() -> TagStore {
        return TagStore()
    }

    // MARK: - Initial State

    @Test func initialStoreHasNoTags() {
        let sut = makeSUT()
        #expect(sut.tags.isEmpty)
        #expect(sut.activeTags.isEmpty)
    }

    @Test func initialStoreHasNoHabitTags() {
        let sut = makeSUT()
        #expect(sut.habitTags.isEmpty)
    }

    // MARK: - Adding Tags

    @Test func addTagAppendsToTags() {
        let sut = makeSUT()

        let tag = sut.addTag(name: "Health")

        #expect(sut.tags.count == 1)
        #expect(tag != nil)
        #expect(tag?.name == "Health")
    }

    @Test func addTagGeneratesUniqueIds() {
        let sut = makeSUT()

        let tag1 = sut.addTag(name: "Health")
        let tag2 = sut.addTag(name: "Fitness")

        #expect(tag1!.id != tag2!.id)
    }

    @Test func addTagSetsTimestamps() {
        let sut = makeSUT()

        let before = Date()
        let tag = sut.addTag(name: "Health")!
        let after = Date()

        #expect(tag.createdAt >= before)
        #expect(tag.createdAt <= after)
        #expect(tag.updatedAt >= before)
        #expect(tag.deletedAt == nil)
    }

    @Test func addTagWithEmptyNameReturnsNil() {
        let sut = makeSUT()

        let tag1 = sut.addTag(name: "")
        #expect(tag1 == nil)
        #expect(sut.tags.isEmpty)

        let tag2 = sut.addTag(name: "   ")
        #expect(tag2 == nil)
        #expect(sut.tags.isEmpty)
    }

    @Test func addTagTrimsWhitespace() {
        let sut = makeSUT()

        let tag = sut.addTag(name: "  Health  ")

        #expect(tag?.name == "Health")
    }

    @Test func addTagUsesProvidedColor() {
        let sut = makeSUT()

        let tag = sut.addTag(name: "Health", colorHex: "#FF0000")

        #expect(tag?.colorHex == "#FF0000")
    }

    @Test func addTagGeneratesRandomColorWhenNoneProvided() {
        let sut = makeSUT()

        let tag = sut.addTag(name: "Health")

        // Should have a valid hex color
        #expect(tag?.colorHex.hasPrefix("#") == true)
        #expect(tag?.colorHex.count == 7)
    }

    // MARK: - Updating Tags

    @Test func updateTagNameChangesName() {
        let sut = makeSUT()
        let tag = sut.addTag(name: "Health")!

        sut.updateTag(id: tag.id, name: "Wellness")

        #expect(sut.tags.first?.name == "Wellness")
    }

    @Test func updateTagColorChangesColor() {
        let sut = makeSUT()
        let tag = sut.addTag(name: "Health", colorHex: "#FF0000")!

        sut.updateTag(id: tag.id, colorHex: "#00FF00")

        #expect(sut.tags.first?.colorHex == "#00FF00")
    }

    @Test func updateTagSetsUpdatedAt() {
        let sut = makeSUT()
        let tag = sut.addTag(name: "Health")!
        let originalUpdatedAt = tag.updatedAt

        sut.updateTag(id: tag.id, name: "Wellness")

        #expect(sut.tags.first!.updatedAt >= originalUpdatedAt)
    }

    @Test func updateNonexistentTagIsNoOp() {
        let sut = makeSUT()
        _ = sut.addTag(name: "Health")

        sut.updateTag(id: "nonexistent", name: "Wellness")

        #expect(sut.tags.first?.name == "Health")
    }

    // MARK: - Soft Delete Tags

    @Test func deleteTagSetsDeletedAt() {
        let sut = makeSUT()
        let tag = sut.addTag(name: "Health")!

        sut.deleteTag(id: tag.id)

        #expect(sut.tags.first?.deletedAt != nil)
    }

    @Test func deletedTagExcludedFromActiveTags() {
        let sut = makeSUT()
        let tag1 = sut.addTag(name: "Health")!
        _ = sut.addTag(name: "Fitness")

        sut.deleteTag(id: tag1.id)

        #expect(sut.activeTags.count == 1)
        #expect(sut.activeTags.first?.name == "Fitness")
    }

    @Test func deleteNonexistentTagIsNoOp() {
        let sut = makeSUT()
        _ = sut.addTag(name: "Health")

        sut.deleteTag(id: "nonexistent")

        #expect(sut.tags.count == 1)
        #expect(sut.activeTags.count == 1)
    }

    // MARK: - Habit-Tag Associations

    @Test func addTagToHabitCreatesHabitTag() {
        let sut = makeSUT()

        sut.addTagToHabit(tagId: "tag-1", habitId: "habit-1")

        #expect(sut.habitTags.count == 1)
        #expect(sut.habitTags.first?.tagId == "tag-1")
        #expect(sut.habitTags.first?.habitId == "habit-1")
    }

    @Test func addTagToHabitDoesNotDuplicateExisting() {
        let sut = makeSUT()

        sut.addTagToHabit(tagId: "tag-1", habitId: "habit-1")
        sut.addTagToHabit(tagId: "tag-1", habitId: "habit-1")

        // Should still be just one active association
        let active = sut.habitTags.filter { $0.deletedAt == nil }
        #expect(active.count == 1)
    }

    @Test func addTagToHabitRestoresSoftDeletedAssociation() {
        let sut = makeSUT()

        sut.addTagToHabit(tagId: "tag-1", habitId: "habit-1")
        sut.removeTagFromHabit(tagId: "tag-1", habitId: "habit-1")

        // Re-add should restore, not create duplicate
        sut.addTagToHabit(tagId: "tag-1", habitId: "habit-1")

        let active = sut.habitTags.filter { $0.deletedAt == nil }
        #expect(active.count == 1)
    }

    @Test func removeTagFromHabitSoftDeletesHabitTag() {
        let sut = makeSUT()

        sut.addTagToHabit(tagId: "tag-1", habitId: "habit-1")
        sut.removeTagFromHabit(tagId: "tag-1", habitId: "habit-1")

        #expect(sut.habitTags.first?.deletedAt != nil)
    }

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
