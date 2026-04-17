import Foundation

// TagStore manages the user-visible tag system: global tags plus the mapping
// between tags and individual habits.
//
// Follows the same pattern as HabitStore — an @Observable class injected via
// @Environment. In React terms, it's another store/context living alongside
// the habit store.
//
// Tags are global (not per-habit) — a tag like "Health" can be applied to
// multiple habits. The association is tracked via HabitTag junction records.
@Observable
@MainActor
final class TagStore {

    // All tags, including soft-deleted ones
    private(set) var tags: [Tag] = []

    // All habit-tag junction records
    private(set) var habitTags: [HabitTag] = []

    // All reward-tag junction records
    private(set) var rewardTags: [RewardTag] = []

    // Tags that haven't been soft-deleted — like activeHabits in HabitStore
    var activeTags: [Tag] {
        tags.filter { $0.deletedAt == nil }
    }

    // MARK: - Tag CRUD

    // Creating a tag either uses the chosen color or assigns one automatically
    // so the tag is immediately distinguishable in the UI.
    @discardableResult
    func addTag(name: String, colorHex: String? = nil) -> Tag? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let now = Date()
        let tag = Tag(
            id: UUID().uuidString,
            name: trimmed,
            // If no color provided, generate a random vibrant one
            colorHex: colorHex ?? ColorGeneration.randomHexColor(),
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )

        tags.append(tag)
        return tag
    }

    // Edits an existing tag. Invalid empty names are rejected because a tag the
    // user can no longer identify is worse than leaving the old name in place.
    func updateTag(id: String, name: String? = nil, colorHex: String? = nil) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }

        let existing = tags[index]

        let newName: String
        if let name = name {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            newName = trimmed
        } else {
            newName = existing.name
        }

        tags[index] = Tag(
            id: existing.id,
            name: newName,
            colorHex: colorHex ?? existing.colorHex,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            deletedAt: existing.deletedAt
        )
    }

    // Soft delete keeps old associations around for sync/history while removing
    // the tag from visible pickers and habit chips.
    func deleteTag(id: String) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }

        let existing = tags[index]
        tags[index] = Tag(
            id: existing.id,
            name: existing.name,
            colorHex: existing.colorHex,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            deletedAt: Date()
        )
    }

    // MARK: - Habit-Tag Associations

    // Toggling a tag back on should revive the old association instead of
    // creating duplicate tag records for the same habit.
    func addTagToHabit(tagId: String, habitId: String) {
        if let index = habitTags.firstIndex(where: {
            $0.tagId == tagId && $0.habitId == habitId
        }) {
            let existing = habitTags[index]
            if existing.deletedAt != nil {
                habitTags[index] = HabitTag(
                    id: existing.id,
                    habitId: existing.habitId,
                    tagId: existing.tagId,
                    createdAt: existing.createdAt,
                    updatedAt: Date(),
                    deletedAt: nil
                )
            }
            return
        }

        let now = Date()
        habitTags.append(HabitTag(
            id: UUID().uuidString,
            habitId: habitId,
            tagId: tagId,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        ))
    }

    // Removing a tag only hides it from the habit; the link is soft-deleted so
    // it can be restored later without inventing a new association.
    func removeTagFromHabit(tagId: String, habitId: String) {
        guard let index = habitTags.firstIndex(where: {
            $0.tagId == tagId && $0.habitId == habitId && $0.deletedAt == nil
        }) else { return }

        let existing = habitTags[index]
        habitTags[index] = HabitTag(
            id: existing.id,
            habitId: existing.habitId,
            tagId: existing.tagId,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            deletedAt: Date()
        )
    }

    // Resolves the set of tags the user should currently see on a habit.
    // Both deleted links and deleted tags are filtered out here.
    func tagsForHabit(habitId: String) -> [Tag] {
        let activeTagIds = Set(
            habitTags
                .filter { $0.habitId == habitId && $0.deletedAt == nil }
                .map(\.tagId)
        )

        return activeTags.filter { activeTagIds.contains($0.id) }
    }

    // Reward tags mirror the habit-tag flow so a reward can reuse the same
    // global tag catalog without needing a second tag CRUD system.
    func addTagToReward(tagId: String, rewardId: String) {
        if let index = rewardTags.firstIndex(where: {
            $0.tagId == tagId && $0.rewardId == rewardId
        }) {
            let existing = rewardTags[index]
            if existing.deletedAt != nil {
                rewardTags[index] = RewardTag(
                    id: existing.id,
                    rewardId: existing.rewardId,
                    tagId: existing.tagId,
                    createdAt: existing.createdAt,
                    updatedAt: Date(),
                    deletedAt: nil
                )
            }
            return
        }

        let now = Date()
        rewardTags.append(RewardTag(
            id: UUID().uuidString,
            rewardId: rewardId,
            tagId: tagId,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        ))
    }

    func removeTagFromReward(tagId: String, rewardId: String) {
        guard let index = rewardTags.firstIndex(where: {
            $0.tagId == tagId && $0.rewardId == rewardId && $0.deletedAt == nil
        }) else { return }

        let existing = rewardTags[index]
        rewardTags[index] = RewardTag(
            id: existing.id,
            rewardId: existing.rewardId,
            tagId: existing.tagId,
            createdAt: existing.createdAt,
            updatedAt: Date(),
            deletedAt: Date()
        )
    }

    func tagsForReward(rewardId: String) -> [Tag] {
        let activeTagIds = Set(
            rewardTags
                .filter { $0.rewardId == rewardId && $0.deletedAt == nil }
                .map(\.tagId)
        )

        return activeTags.filter { activeTagIds.contains($0.id) }
    }

    func tags(for target: TagAssignmentTarget) -> [Tag] {
        switch target {
        case .habit(let habitId):
            return tagsForHabit(habitId: habitId)
        case .reward(let rewardId):
            return tagsForReward(rewardId: rewardId)
        }
    }

    func addTag(tagId: String, to target: TagAssignmentTarget) {
        switch target {
        case .habit(let habitId):
            addTagToHabit(tagId: tagId, habitId: habitId)
        case .reward(let rewardId):
            addTagToReward(tagId: tagId, rewardId: rewardId)
        }
    }

    func removeTag(tagId: String, from target: TagAssignmentTarget) {
        switch target {
        case .habit(let habitId):
            removeTagFromHabit(tagId: tagId, habitId: habitId)
        case .reward(let rewardId):
            removeTagFromReward(tagId: tagId, rewardId: rewardId)
        }
    }
}
