import Foundation

@MainActor
enum NewEntityFormTagAssignmentSupport {
    static func synchronizeSharedTags(
        _ sharedTagIDs: [RecordID],
        taskID: RecordID,
        recurringTaskID: RecordID,
        rewardID: RecordID,
        tagStore: TagStore,
        shouldNotifySync: Bool = true
    ) {
        let desiredTagIDs = Set(sharedTagIDs)

        for target in allTargets(taskID: taskID, recurringTaskID: recurringTaskID, rewardID: rewardID) {
            synchronize(desiredTagIDs, target: target, tagStore: tagStore, shouldNotifySync: shouldNotifySync)
        }
    }

    static func cleanupDraftTags(
        taskID: RecordID,
        recurringTaskID: RecordID,
        rewardID: RecordID,
        preserving preservedEntity: EntityFormKind?,
        tagStore: TagStore,
        shouldNotifySync: Bool = true
    ) {
        let preservedTarget = preservedEntity.map {
            target(for: $0, taskID: taskID, recurringTaskID: recurringTaskID, rewardID: rewardID)
        }

        for target in allTargets(taskID: taskID, recurringTaskID: recurringTaskID, rewardID: rewardID) where target != preservedTarget {
            for tagID in tagStore.tags(for: target).map(\.id) {
                tagStore.removeTag(tagId: tagID, from: target, shouldNotifySync: shouldNotifySync)
            }
        }
    }

    private static func synchronize(
        _ desiredTagIDs: Set<RecordID>,
        target: TagAssignmentTarget,
        tagStore: TagStore,
        shouldNotifySync: Bool
    ) {
        let currentTagIDs = Set(tagStore.tags(for: target).map(\.id))

        for tagID in currentTagIDs.subtracting(desiredTagIDs) {
            tagStore.removeTag(tagId: tagID, from: target, shouldNotifySync: shouldNotifySync)
        }

        for tagID in desiredTagIDs.subtracting(currentTagIDs) {
            tagStore.addTag(tagId: tagID, to: target, shouldNotifySync: shouldNotifySync)
        }
    }

    private static func allTargets(
        taskID: RecordID,
        recurringTaskID: RecordID,
        rewardID: RecordID
    ) -> [TagAssignmentTarget] {
        [
            .task(taskID),
            .recurringTask(recurringTaskID),
            .reward(rewardID)
        ]
    }

    private static func target(
        for entity: EntityFormKind,
        taskID: RecordID,
        recurringTaskID: RecordID,
        rewardID: RecordID
    ) -> TagAssignmentTarget {
        switch entity {
        case .task:
            return .task(taskID)
        case .recurringTask:
            return .recurringTask(recurringTaskID)
        case .reward:
            return .reward(rewardID)
        }
    }
}
