import Testing
@testable import tofustash

@MainActor
struct ListPreferencesStoreTests {

    // Behaviour: After the user customizes the habits list, the app should reopen
    // with the same sort and selected tag filters still active.
    @Test("Habit list preferences persist across store relaunch")
    func habitPreferencesPersistAcrossRelaunch() {
        let storageURL = TestHelpers.makeTemporaryFileURL("persisted-habit-list-preferences")
        let tagID: RecordID = "focus"

        let firstStore = ListPreferencesStore(storageURL: storageURL)
        firstStore.setHabitSort(.difficultyLowToHigh)
        firstStore.toggleHabitTag(tagID)

        let relaunchedStore = ListPreferencesStore(storageURL: storageURL)

        #expect(relaunchedStore.habitPreferences.sort == .difficultyLowToHigh)
        #expect(relaunchedStore.habitPreferences.selectedTagIDs == [tagID])
    }

    // Behaviour: Reward list controls are independent from habits, so a user can
    // keep different saved views for earning and spending lists.
    @Test("Reward list preferences persist without changing habit preferences")
    func rewardPreferencesPersistIndependently() {
        let storageURL = TestHelpers.makeTemporaryFileURL("persisted-reward-list-preferences")
        let rewardTagID: RecordID = "treat"

        let firstStore = ListPreferencesStore(storageURL: storageURL)
        firstStore.setRewardSort(.oldestToNewest)
        firstStore.toggleRewardTag(rewardTagID)

        let relaunchedStore = ListPreferencesStore(storageURL: storageURL)

        #expect(relaunchedStore.rewardPreferences.sort == .oldestToNewest)
        #expect(relaunchedStore.rewardPreferences.selectedTagIDs == [rewardTagID])
        #expect(relaunchedStore.habitPreferences == EntityListPreferences())
    }

    // Behaviour: If a tag disappears from the habits filter list, the app should
    // drop that stale saved tag id so reopening the list does not stay filtered by
    // something the user can no longer see or uncheck.
    @Test("Habit selected tags are pruned when they are no longer valid")
    func sanitizeHabitSelectedTagsRemovesStaleIDs() {
        let storageURL = TestHelpers.makeTemporaryFileURL("sanitize-habit-list-preferences")
        let focus: RecordID = "focus"
        let stale: RecordID = "deleted-tag"

        let store = ListPreferencesStore(storageURL: storageURL)
        store.toggleHabitTag(focus)
        store.toggleHabitTag(stale)

        let didChange = store.sanitizeHabitSelectedTags(validTagIDs: [focus])
        let relaunchedStore = ListPreferencesStore(storageURL: storageURL)

        #expect(didChange)
        #expect(store.habitPreferences.selectedTagIDs == [focus])
        #expect(relaunchedStore.habitPreferences.selectedTagIDs == [focus])
    }

    // Behaviour: Reward filters should fully clear their selected tag chips if
    // every saved tag has disappeared from the current owner tag catalog.
    @Test("Reward selected tags clear when all saved ids are stale")
    func sanitizeRewardSelectedTagsClearsAllStaleIDs() {
        let storageURL = TestHelpers.makeTemporaryFileURL("sanitize-reward-list-preferences")
        let store = ListPreferencesStore(storageURL: storageURL)

        store.toggleRewardTag("deleted-tag")

        let didChange = store.sanitizeRewardSelectedTags(validTagIDs: [])
        let relaunchedStore = ListPreferencesStore(storageURL: storageURL)

        #expect(didChange)
        #expect(store.rewardPreferences.selectedTagIDs.isEmpty)
        #expect(relaunchedStore.rewardPreferences.selectedTagIDs.isEmpty)
    }

    // Behaviour: When the user switches to another local owner bucket, any tag ids
    // that do not exist in that owner's current tag catalog should be removed.
    @Test("Owner switching can prune stale habit selected tag ids")
    func ownerSwitchingCanPruneStaleHabitSelectedTagIDs() {
        let storageURL = TestHelpers.makeTemporaryFileURL("owner-switch-habit-list-preferences")
        let store = ListPreferencesStore(storageURL: storageURL, initialOwnerID: "user-a")

        store.toggleHabitTag("focus")
        store.setCurrentOwner("user-b")
        store.toggleHabitTag("stale")
        store.sanitizeHabitSelectedTags(validTagIDs: [])

        #expect(store.habitPreferences.selectedTagIDs.isEmpty)

        store.setCurrentOwner("user-a")
        #expect(store.habitPreferences.selectedTagIDs == ["focus"])
    }
}
