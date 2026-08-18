import Foundation
import Testing
@testable import bochi

@MainActor
struct NewEntityFormTagAssignmentSupportTests {
    // Behaviour: dismissing the unified draft should clean up every temporary
    // tag assignment so abandoned ids never leak into the saved stores.
    @Test func cleanupOnDiscardRemovesEveryDraftTagAssignment() {
        let storageURL = TestHelpers.makeTemporaryFileURL("new-entity-draft-tags-discard")
        let tagStore = TagStore(storageURL: storageURL)
        let taskID = RecordID("task-draft")
        let recurringTaskID = RecordID("recurringTask-draft")
        let rewardID = RecordID("reward-draft")
        let tag = tagStore.addTag(name: "Shared")!

        NewEntityFormTagAssignmentSupport.synchronizeSharedTags(
            [tag.id],
            taskID: taskID,
            recurringTaskID: recurringTaskID,
            rewardID: rewardID,
            tagStore: tagStore
        )

        NewEntityFormTagAssignmentSupport.cleanupDraftTags(
            taskID: taskID,
            recurringTaskID: recurringTaskID,
            rewardID: rewardID,
            preserving: nil,
            tagStore: tagStore
        )

        #expect(tagStore.tagsForTask(taskId: taskID).isEmpty)
        #expect(tagStore.tagsForRecurringTask(recurringTaskId: recurringTaskID).isEmpty)
        #expect(tagStore.tagsForReward(rewardId: rewardID).isEmpty)
    }

    // Behaviour: saving one entity from the unified draft should keep tags for
    // the created entity only and remove the temporary copies for the others.
    @Test func cleanupOnPersistPreservesOnlyCreatedEntityTags() {
        let storageURL = TestHelpers.makeTemporaryFileURL("new-entity-draft-tags-persist")
        let tagStore = TagStore(storageURL: storageURL)
        let taskID = RecordID("task-draft")
        let recurringTaskID = RecordID("recurringTask-draft")
        let rewardID = RecordID("reward-draft")
        let tag = tagStore.addTag(name: "Shared")!

        NewEntityFormTagAssignmentSupport.synchronizeSharedTags(
            [tag.id],
            taskID: taskID,
            recurringTaskID: recurringTaskID,
            rewardID: rewardID,
            tagStore: tagStore
        )

        NewEntityFormTagAssignmentSupport.cleanupDraftTags(
            taskID: taskID,
            recurringTaskID: recurringTaskID,
            rewardID: rewardID,
            preserving: .recurringTask,
            tagStore: tagStore
        )

        #expect(tagStore.tagsForTask(taskId: taskID).isEmpty)
        #expect(tagStore.tagsForRecurringTask(recurringTaskId: recurringTaskID).map(\.id) == [tag.id])
        #expect(tagStore.tagsForReward(rewardId: rewardID).isEmpty)
    }

    // Behaviour: while the unified form mirrors tags across temporary draft ids,
    // those unsaved task/recurringTask/reward ids should not be queued for sync.
    @Test func draftTagMirroringCanStayLocalOnly() {
        let storageURL = TestHelpers.makeTemporaryFileURL("new-entity-draft-tags-local-only")
        let ownerID = "user-123"
        let tagStore = TagStore(storageURL: storageURL, initialOwnerID: ownerID)
        let syncStateStore = SyncStateStore(storageURL: storageURL)
        let taskID = RecordID("task-draft")
        let recurringTaskID = RecordID("recurringTask-draft")
        let rewardID = RecordID("reward-draft")
        let tag = tagStore.addTag(name: "Shared", shouldNotifySync: false)!

        NewEntityFormTagAssignmentSupport.synchronizeSharedTags(
            [tag.id],
            taskID: taskID,
            recurringTaskID: recurringTaskID,
            rewardID: rewardID,
            tagStore: tagStore,
            shouldNotifySync: false
        )

        let dirty = syncStateStore.state(for: ownerID).dirty
        #expect(dirty.taskTags.isEmpty)
        #expect(dirty.recurringTaskTags.isEmpty)
        #expect(dirty.rewardTags.isEmpty)
    }

    // Behaviour: after the user saves one entity type, only that saved entity's
    // tag assignment should be dirty; deleted draft copies should stay local.
    @Test func persistedTagAssignmentCanBeSyncedWithoutDraftCopies() {
        let storageURL = TestHelpers.makeTemporaryFileURL("new-entity-draft-tags-persisted-sync")
        let ownerID = "user-123"
        let tagStore = TagStore(storageURL: storageURL, initialOwnerID: ownerID)
        let syncStateStore = SyncStateStore(storageURL: storageURL)
        let taskID = RecordID("task-draft")
        let recurringTaskID = RecordID("recurringTask-draft")
        let rewardID = RecordID("reward-draft")
        let tag = tagStore.addTag(name: "Shared", shouldNotifySync: false)!

        NewEntityFormTagAssignmentSupport.synchronizeSharedTags(
            [tag.id],
            taskID: taskID,
            recurringTaskID: recurringTaskID,
            rewardID: rewardID,
            tagStore: tagStore,
            shouldNotifySync: false
        )
        tagStore.addTag(tagId: tag.id, to: .recurringTask(recurringTaskID))
        NewEntityFormTagAssignmentSupport.cleanupDraftTags(
            taskID: taskID,
            recurringTaskID: recurringTaskID,
            rewardID: rewardID,
            preserving: .recurringTask,
            tagStore: tagStore,
            shouldNotifySync: false
        )

        let dirty = syncStateStore.state(for: ownerID).dirty
        #expect(dirty.taskTags.isEmpty)
        #expect(dirty.recurringTaskTags.map(\.id) == [RecordID("\(recurringTaskID):\(tag.id)")])
        #expect(dirty.rewardTags.isEmpty)
    }
}
