import Foundation

// This store is the Swift equivalent of a tiny Zustand slice backed by disk.
// SwiftUI views read `habitPreferences` / `rewardPreferences` from the
// environment, and every mutating method writes through to JSON immediately.
@Observable
@MainActor
final class ListPreferencesStore {
    enum ListScope {
        case habits
        case rewards
    }

    private struct PersistedState: Codable {
        var habitPreferencesByOwner: [String: EntityListPreferences] = [:]
        var rewardPreferencesByOwner: [String: EntityListPreferences] = [:]
    }

    private let storageURL: URL
    private(set) var currentOwnerID: String
    private var habitPreferencesByOwner: [String: EntityListPreferences]
    private var rewardPreferencesByOwner: [String: EntityListPreferences]

    private(set) var habitPreferences: EntityListPreferences
    private(set) var rewardPreferences: EntityListPreferences

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = StorageOwner.local
    ) {
        self.storageURL = storageURL ?? AppStorageLocation.fileURL(filename: "list-preferences")
        self.currentOwnerID = initialOwnerID

        let persisted = JSONFileStore.load(PersistedState.self, from: self.storageURL, defaultValue: PersistedState())
        self.habitPreferencesByOwner = persisted.habitPreferencesByOwner
        self.rewardPreferencesByOwner = persisted.rewardPreferencesByOwner
        self.habitPreferences = persisted.habitPreferencesByOwner[initialOwnerID] ?? EntityListPreferences()
        self.rewardPreferences = persisted.rewardPreferencesByOwner[initialOwnerID] ?? EntityListPreferences()
    }

    // Like swapping which persisted user bucket your selector points at.
    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        habitPreferences = habitPreferencesByOwner[ownerID] ?? EntityListPreferences()
        rewardPreferences = rewardPreferencesByOwner[ownerID] ?? EntityListPreferences()
    }

    func migratePreferences(from sourceOwnerID: String, to destinationOwnerID: String) -> Bool {
        guard sourceOwnerID != destinationOwnerID else { return false }

        var migrated = false

        if let sourceHabitPreferences = habitPreferencesByOwner[sourceOwnerID] {
            habitPreferencesByOwner[destinationOwnerID] = sourceHabitPreferences
            habitPreferencesByOwner[sourceOwnerID] = nil
            migrated = true
        }

        if let sourceRewardPreferences = rewardPreferencesByOwner[sourceOwnerID] {
            rewardPreferencesByOwner[destinationOwnerID] = sourceRewardPreferences
            rewardPreferencesByOwner[sourceOwnerID] = nil
            migrated = true
        }

        if migrated {
            persist()
            setCurrentOwner(currentOwnerID)
        }

        return migrated
    }

    func setHabitSort(_ sort: EntityListSortOption) {
        mutatePreferences(for: .habits) { $0.sort = sort }
    }

    func setRewardSort(_ sort: EntityListSortOption) {
        mutatePreferences(for: .rewards) { $0.sort = sort }
    }

    func setHabitDifficultyFilter(_ filter: EntityListOptionalFieldFilter) {
        mutatePreferences(for: .habits) { $0.difficultyFilter = filter }
    }

    func setRewardDifficultyFilter(_ filter: EntityListOptionalFieldFilter) {
        mutatePreferences(for: .rewards) { $0.difficultyFilter = filter }
    }

    func setHabitFrequencyFilter(_ filter: EntityListOptionalFieldFilter) {
        mutatePreferences(for: .habits) { $0.frequencyFilter = filter }
    }

    func setRewardFrequencyFilter(_ filter: EntityListOptionalFieldFilter) {
        mutatePreferences(for: .rewards) { $0.frequencyFilter = filter }
    }

    func setHabitTagMatchMode(_ mode: EntityListTagMatchMode) {
        mutatePreferences(for: .habits) { $0.tagMatchMode = mode }
    }

    func setRewardTagMatchMode(_ mode: EntityListTagMatchMode) {
        mutatePreferences(for: .rewards) { $0.tagMatchMode = mode }
    }

    func toggleHabitTag(_ tagID: RecordID) {
        mutatePreferences(for: .habits) { preferences in
            toggleTag(tagID, in: &preferences)
        }
    }

    func toggleRewardTag(_ tagID: RecordID) {
        mutatePreferences(for: .rewards) { preferences in
            toggleTag(tagID, in: &preferences)
        }
    }

    func clearHabitFilters() {
        clearFilters(for: .habits)
    }

    func clearRewardFilters() {
        clearFilters(for: .rewards)
    }

    @discardableResult
    func sanitizeHabitSelectedTags(validTagIDs: Set<RecordID>) -> Bool {
        sanitizeSelectedTags(for: .habits, validTagIDs: validTagIDs)
    }

    @discardableResult
    func sanitizeRewardSelectedTags(validTagIDs: Set<RecordID>) -> Bool {
        sanitizeSelectedTags(for: .rewards, validTagIDs: validTagIDs)
    }

    @discardableResult
    func sanitizeSelectedTags(
        validHabitTagIDs: Set<RecordID>,
        validRewardTagIDs: Set<RecordID>
    ) -> Bool {
        let habitsChanged = sanitizeHabitSelectedTags(validTagIDs: validHabitTagIDs)
        let rewardsChanged = sanitizeRewardSelectedTags(validTagIDs: validRewardTagIDs)
        return habitsChanged || rewardsChanged
    }

    private func toggleTag(_ tagID: RecordID, in preferences: inout EntityListPreferences) {
        if let index = preferences.selectedTagIDs.firstIndex(of: tagID) {
            preferences.selectedTagIDs.remove(at: index)
        } else {
            preferences.selectedTagIDs.append(tagID)
            preferences.selectedTagIDs.sort { $0.rawValue < $1.rawValue }
        }
    }

    private func clearFilters(for scope: ListScope) {
        mutatePreferences(for: scope) { preferences in
            preferences.difficultyFilter = .any
            preferences.frequencyFilter = .any
            preferences.selectedTagIDs = []
            preferences.tagMatchMode = .any
        }
    }

    @discardableResult
    private func sanitizeSelectedTags(for scope: ListScope, validTagIDs: Set<RecordID>) -> Bool {
        var didChange = false
        mutatePreferences(for: scope) { preferences in
            let sanitized = preferences.selectedTagIDs.filter { validTagIDs.contains($0) }
            if sanitized != preferences.selectedTagIDs {
                preferences.selectedTagIDs = sanitized
                didChange = true
            }
        }
        return didChange
    }

    private func mutatePreferences(for scope: ListScope, _ mutate: (inout EntityListPreferences) -> Void) {
        // `inout` here is the closest Swift syntax to mutating a draft object
        // in Immer, then committing the next immutable snapshot to the store.
        let current = preferences(for: scope)
        var next = current
        mutate(&next)
        guard next != current else { return }
        setPreferences(next, for: scope)
        persist()
    }

    private func preferences(for scope: ListScope) -> EntityListPreferences {
        switch scope {
        case .habits:
            habitPreferences
        case .rewards:
            rewardPreferences
        }
    }

    private func setPreferences(_ preferences: EntityListPreferences, for scope: ListScope) {
        switch scope {
        case .habits:
            habitPreferences = preferences
            habitPreferencesByOwner[currentOwnerID] = preferences
        case .rewards:
            rewardPreferences = preferences
            rewardPreferencesByOwner[currentOwnerID] = preferences
        }
    }

    private func persist() {
        JSONFileStore.save(
            PersistedState(
                habitPreferencesByOwner: habitPreferencesByOwner,
                rewardPreferencesByOwner: rewardPreferencesByOwner
            ),
            to: storageURL
        )
    }
}
