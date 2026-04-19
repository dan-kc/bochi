import Foundation

// This store is the Swift equivalent of a tiny Zustand slice backed by disk.
// SwiftUI views read `habitPreferences` / `rewardPreferences` from the
// environment, and every mutating method writes through to JSON immediately.
@Observable
@MainActor
final class ListPreferencesStore {
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
        mutateHabitPreferences { $0.sort = sort }
    }

    func setRewardSort(_ sort: EntityListSortOption) {
        mutateRewardPreferences { $0.sort = sort }
    }

    func setHabitDifficultyFilter(_ filter: EntityListOptionalFieldFilter) {
        mutateHabitPreferences { $0.difficultyFilter = filter }
    }

    func setRewardDifficultyFilter(_ filter: EntityListOptionalFieldFilter) {
        mutateRewardPreferences { $0.difficultyFilter = filter }
    }

    func setHabitFrequencyFilter(_ filter: EntityListOptionalFieldFilter) {
        mutateHabitPreferences { $0.frequencyFilter = filter }
    }

    func setRewardFrequencyFilter(_ filter: EntityListOptionalFieldFilter) {
        mutateRewardPreferences { $0.frequencyFilter = filter }
    }

    func setHabitTagMatchMode(_ mode: EntityListTagMatchMode) {
        mutateHabitPreferences { $0.tagMatchMode = mode }
    }

    func setRewardTagMatchMode(_ mode: EntityListTagMatchMode) {
        mutateRewardPreferences { $0.tagMatchMode = mode }
    }

    func toggleHabitTag(_ tagID: RecordID) {
        mutateHabitPreferences { preferences in
            toggleTag(tagID, in: &preferences)
        }
    }

    func toggleRewardTag(_ tagID: RecordID) {
        mutateRewardPreferences { preferences in
            toggleTag(tagID, in: &preferences)
        }
    }

    func clearHabitFilters() {
        mutateHabitPreferences { preferences in
            preferences.difficultyFilter = .any
            preferences.frequencyFilter = .any
            preferences.selectedTagIDs = []
            preferences.tagMatchMode = .any
        }
    }

    func clearRewardFilters() {
        mutateRewardPreferences { preferences in
            preferences.difficultyFilter = .any
            preferences.frequencyFilter = .any
            preferences.selectedTagIDs = []
            preferences.tagMatchMode = .any
        }
    }

    private func toggleTag(_ tagID: RecordID, in preferences: inout EntityListPreferences) {
        if let index = preferences.selectedTagIDs.firstIndex(of: tagID) {
            preferences.selectedTagIDs.remove(at: index)
        } else {
            preferences.selectedTagIDs.append(tagID)
            preferences.selectedTagIDs.sort { $0.rawValue < $1.rawValue }
        }
    }

    private func mutateHabitPreferences(_ mutate: (inout EntityListPreferences) -> Void) {
        // `inout` here is the closest Swift syntax to mutating a draft object
        // in Immer, then committing the next immutable snapshot to the store.
        var next = habitPreferences
        mutate(&next)
        habitPreferences = next
        habitPreferencesByOwner[currentOwnerID] = next
        persist()
    }

    private func mutateRewardPreferences(_ mutate: (inout EntityListPreferences) -> Void) {
        var next = rewardPreferences
        mutate(&next)
        rewardPreferences = next
        rewardPreferencesByOwner[currentOwnerID] = next
        persist()
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
