import Foundation
import Testing
@testable import bochi

@MainActor
struct TagStoreTests {

    private func makeSUT() -> TagStore {
        return TagStore(storageURL: TestHelpers.makeTemporaryFileURL("tags"))
    }

    // MARK: - Initial State

    // Behaviour: When the app first loads with no data, the tag list is empty.
    @Test func initialStoreIsEmpty() {
        let sut = makeSUT()
        #expect(sut.tags.isEmpty)
        #expect(sut.activeTags.isEmpty)
        #expect(sut.recurringTaskTags.isEmpty)
        #expect(sut.rewardTags.isEmpty)
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

    // MARK: - RecurringTask-Tag Associations

    // Behaviour: When a user assigns a tag to a recurringTask, the association is created.
    @Test func addTagToRecurringTaskCreatesRecurringTaskTag() {
        let sut = makeSUT()

        sut.addTagToRecurringTask(tagId: "tag-1", recurringTaskId: "recurringTask-1")

        #expect(sut.recurringTaskTags.count == 1)
        #expect(sut.recurringTaskTags.first?.tagId == "tag-1")
        #expect(sut.recurringTaskTags.first?.recurringTaskId == "recurringTask-1")
    }

    // Behaviour: When a user taps the same tag twice on a recurringTask (e.g. toggling),
    // only one association exists — no duplicates.
    @Test func addTagToRecurringTaskDoesNotDuplicateExisting() {
        let sut = makeSUT()

        sut.addTagToRecurringTask(tagId: "tag-1", recurringTaskId: "recurringTask-1")
        sut.addTagToRecurringTask(tagId: "tag-1", recurringTaskId: "recurringTask-1")

        // Should still be just one active association
        let active = sut.recurringTaskTags.filter { $0.deletedAt == nil }
        #expect(active.count == 1)
    }

    // Behaviour: When a user removes a tag from a recurringTask and then re-adds it,
    // the existing association is restored (not duplicated).
    @Test func addTagToRecurringTaskRestoresSoftDeletedAssociation() {
        let sut = makeSUT()

        sut.addTagToRecurringTask(tagId: "tag-1", recurringTaskId: "recurringTask-1")
        sut.removeTagFromRecurringTask(tagId: "tag-1", recurringTaskId: "recurringTask-1")

        // Re-add should restore, not create duplicate
        sut.addTagToRecurringTask(tagId: "tag-1", recurringTaskId: "recurringTask-1")

        let active = sut.recurringTaskTags.filter { $0.deletedAt == nil }
        #expect(active.count == 1)
    }

    // Behaviour: When a user removes a tag from a recurringTask, the association is
    // soft-deleted (preserving history for sync).
    @Test func removeTagFromRecurringTaskSoftDeletesRecurringTaskTag() {
        let sut = makeSUT()

        sut.addTagToRecurringTask(tagId: "tag-1", recurringTaskId: "recurringTask-1")
        sut.removeTagFromRecurringTask(tagId: "tag-1", recurringTaskId: "recurringTask-1")

        #expect(sut.recurringTaskTags.first?.deletedAt != nil)
    }

    // Behaviour: When viewing a recurringTask's details, the user sees only the tags
    // currently assigned to that recurringTask.
    @Test func tagsForRecurringTaskReturnsCorrectTags() {
        let sut = makeSUT()
        let tag1 = sut.addTag(name: "Health")!
        let tag2 = sut.addTag(name: "Fitness")!
        _ = sut.addTag(name: "Unrelated")

        sut.addTagToRecurringTask(tagId: tag1.id, recurringTaskId: "recurringTask-1")
        sut.addTagToRecurringTask(tagId: tag2.id, recurringTaskId: "recurringTask-1")

        let tags = sut.tagsForRecurringTask(recurringTaskId: "recurringTask-1")
        #expect(tags.count == 2)
        #expect(tags.contains(where: { $0.name == "Health" }))
        #expect(tags.contains(where: { $0.name == "Fitness" }))
    }

    // Behaviour: When a user removes a tag from a recurringTask, it no longer appears
    // in that recurringTask's tag list.
    @Test func tagsForRecurringTaskExcludesRemovedTags() {
        let sut = makeSUT()
        let tag1 = sut.addTag(name: "Health")!
        let tag2 = sut.addTag(name: "Fitness")!

        sut.addTagToRecurringTask(tagId: tag1.id, recurringTaskId: "recurringTask-1")
        sut.addTagToRecurringTask(tagId: tag2.id, recurringTaskId: "recurringTask-1")
        sut.removeTagFromRecurringTask(tagId: tag1.id, recurringTaskId: "recurringTask-1")

        let tags = sut.tagsForRecurringTask(recurringTaskId: "recurringTask-1")
        #expect(tags.count == 1)
        #expect(tags.first?.name == "Fitness")
    }

    // Behaviour: When a tag itself is deleted, it no longer appears on any recurringTask
    // that had it assigned — even though the recurringTask-tag association still exists.
    @Test func tagsForRecurringTaskExcludesDeletedTags() {
        let sut = makeSUT()
        let tag1 = sut.addTag(name: "Health")!

        sut.addTagToRecurringTask(tagId: tag1.id, recurringTaskId: "recurringTask-1")
        sut.deleteTag(id: tag1.id)

        // Tag itself is deleted — should not appear even though association exists
        let tags = sut.tagsForRecurringTask(recurringTaskId: "recurringTask-1")
        #expect(tags.isEmpty)
    }

    // Behaviour: When a user assigns a tag to a task, the association is created.
    @Test func addTagToTaskCreatesTaskTag() {
        let sut = makeSUT()

        sut.addTagToTask(tagId: "tag-1", taskId: "task-1")

        #expect(sut.taskTags.count == 1)
        #expect(sut.taskTags.first?.tagId == "tag-1")
        #expect(sut.taskTags.first?.taskId == "task-1")
    }

    // Behaviour: Task details should show only the tags currently assigned to that task.
    @Test func tagsForTaskReturnsCorrectTags() {
        let sut = makeSUT()
        let urgent = sut.addTag(name: "Urgent")!
        let admin = sut.addTag(name: "Admin")!

        sut.addTagToTask(tagId: urgent.id, taskId: "task-1")
        sut.addTagToTask(tagId: admin.id, taskId: "task-1")

        let tags = sut.tagsForTask(taskId: "task-1")
        #expect(tags.map(\.id) == [urgent.id, admin.id])
    }

    // Behaviour: When a user assigns a shared tag to a reward, the reward gets
    // the same tag chip style and catalog entry as recurringTasks.
    @Test func addTagToRewardCreatesRewardTag() {
        let sut = makeSUT()

        sut.addTagToReward(tagId: "tag-1", rewardId: "reward-1")

        #expect(sut.rewardTags.count == 1)
        #expect(sut.rewardTags.first?.tagId == "tag-1")
        #expect(sut.rewardTags.first?.rewardId == "reward-1")
    }

    // Behaviour: When a user re-adds a previously removed reward tag, the old
    // association is restored instead of creating duplicates.
    @Test func addTagToRewardRestoresSoftDeletedAssociation() {
        let sut = makeSUT()

        sut.addTagToReward(tagId: "tag-1", rewardId: "reward-1")
        sut.removeTagFromReward(tagId: "tag-1", rewardId: "reward-1")
        sut.addTagToReward(tagId: "tag-1", rewardId: "reward-1")

        let active = sut.rewardTags.filter { $0.deletedAt == nil }
        #expect(active.count == 1)
    }

    // Behaviour: When the reward screen renders a reward, it only shows tags
    // actively assigned to that reward.
    @Test func tagsForRewardReturnsCorrectTags() {
        let sut = makeSUT()
        let focus = sut.addTag(name: "Focus")!
        let comfort = sut.addTag(name: "Comfort")!

        sut.addTagToReward(tagId: focus.id, rewardId: "reward-1")
        sut.addTagToReward(tagId: comfort.id, rewardId: "reward-1")

        let tags = sut.tagsForReward(rewardId: "reward-1")
        #expect(tags.count == 2)
        #expect(tags.contains(where: { $0.id == focus.id }))
        #expect(tags.contains(where: { $0.id == comfort.id }))
    }
}
