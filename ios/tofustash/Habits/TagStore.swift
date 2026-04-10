import Foundation

// TagStore manages tags and the many-to-many relationship between tags and habits.
// Follows the same pattern as HabitStore — an @Observable class injected via
// @Environment. In React terms, it's a second context/store that lives
// alongside HabitStore.
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

    // Tags that haven't been soft-deleted — like activeHabits in HabitStore
    var activeTags: [Tag] {
        tags.filter { $0.deletedAt == nil }
    }

    // MARK: - Tag CRUD

    // Creates a new tag. Generates a random color if none provided.
    // Returns nil if name is empty or whitespace-only.
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

    // Updates a tag's name and/or color. Pass nil for fields you don't want to change.
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

    // Soft-deletes a tag by setting its deletedAt timestamp
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

    // Adds a tag to a habit. If a soft-deleted association already exists,
    // restores it instead of creating a duplicate.
    func addTagToHabit(tagId: String, habitId: String) {
        // Check if association already exists (active or deleted)
        if let index = habitTags.firstIndex(where: {
            $0.tagId == tagId && $0.habitId == habitId
        }) {
            let existing = habitTags[index]
            // If it's active, no-op. If deleted, restore it.
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

        // Create new association
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

    // Removes a tag from a habit via soft-delete on the junction record
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

    // Returns the active tags applied to a specific habit.
    // Filters out both soft-deleted associations AND soft-deleted tags.
    func tagsForHabit(habitId: String) -> [Tag] {
        // Get active tag IDs for this habit
        let activeTagIds = Set(
            habitTags
                .filter { $0.habitId == habitId && $0.deletedAt == nil }
                .map(\.tagId)
        )

        // Return matching tags that are themselves not deleted
        return activeTags.filter { activeTagIds.contains($0.id) }
    }
}
