import Testing
@testable import bochi

@MainActor
struct ListPreferencesStoreTests {

    // Behaviour: After the user customizes the recurringTasks list, the app should reopen
    // with the same sort and hidden tag toggles still active.
    @Test("RecurringTask list preferences persist across store relaunch")
    func recurringTaskPreferencesPersistAcrossRelaunch() {
        let storageURL = TestHelpers.makeTemporaryFileURL("persisted-recurringTask-list-preferences")
        let tagID: RecordID = "focus"

        let firstStore = ListPreferencesStore(storageURL: storageURL)
        firstStore.setRecurringTaskSort(.oldestToNewest)
        firstStore.toggleRecurringTaskTag(tagID)

        let relaunchedStore = ListPreferencesStore(storageURL: storageURL)

        #expect(relaunchedStore.recurringTaskPreferences.sort == .oldestToNewest)
        #expect(relaunchedStore.recurringTaskPreferences.hiddenTagIDs == [tagID])
    }

    // Behaviour: Reward list controls are independent from recurringTasks, so a user can
    // keep different saved views for earning and spending lists.
    @Test("Reward list preferences persist without changing recurringTask preferences")
    func rewardPreferencesPersistIndependently() {
        let storageURL = TestHelpers.makeTemporaryFileURL("persisted-reward-list-preferences")
        let rewardTagID: RecordID = "treat"

        let firstStore = ListPreferencesStore(storageURL: storageURL)
        firstStore.setRewardSort(.oldestToNewest)
        firstStore.toggleRewardTag(rewardTagID)

        let relaunchedStore = ListPreferencesStore(storageURL: storageURL)

        #expect(relaunchedStore.rewardPreferences.sort == .oldestToNewest)
        #expect(relaunchedStore.rewardPreferences.hiddenTagIDs == [rewardTagID])
        #expect(relaunchedStore.recurringTaskPreferences == EntityListPreferences())
    }

    // Behaviour: If a tag disappears from the recurringTasks filter list, the app should
    // drop that stale hidden tag id so reopening the list does not stay filtered
    // by something the user can no longer see or re-enable.
    @Test("RecurringTask hidden tags are pruned when they are no longer valid")
    func sanitizeRecurringTaskSelectedTagsRemovesStaleIDs() {
        let storageURL = TestHelpers.makeTemporaryFileURL("sanitize-recurringTask-list-preferences")
        let focus: RecordID = "focus"
        let stale: RecordID = "deleted-tag"

        let store = ListPreferencesStore(storageURL: storageURL)
        store.toggleRecurringTaskTag(focus)
        store.toggleRecurringTaskTag(stale)

        let didChange = store.sanitizeRecurringTaskSelectedTags(validTagIDs: [focus])
        let relaunchedStore = ListPreferencesStore(storageURL: storageURL)

        #expect(didChange)
        #expect(store.recurringTaskPreferences.hiddenTagIDs == [focus])
        #expect(relaunchedStore.recurringTaskPreferences.hiddenTagIDs == [focus])
    }

    // Behaviour: Reward filters should fully clear their hidden tag chips if
    // every saved tag has disappeared from the current owner tag catalog.
    @Test("Reward hidden tags clear when all saved ids are stale")
    func sanitizeRewardSelectedTagsClearsAllStaleIDs() {
        let storageURL = TestHelpers.makeTemporaryFileURL("sanitize-reward-list-preferences")
        let store = ListPreferencesStore(storageURL: storageURL)

        store.toggleRewardTag("deleted-tag")

        let didChange = store.sanitizeRewardSelectedTags(validTagIDs: [])
        let relaunchedStore = ListPreferencesStore(storageURL: storageURL)

        #expect(didChange)
        #expect(store.rewardPreferences.hiddenTagIDs.isEmpty)
        #expect(relaunchedStore.rewardPreferences.hiddenTagIDs.isEmpty)
    }

    // Behaviour: When the user switches to another local owner bucket, any tag ids
    // that do not exist in that owner's current tag catalog should be removed.
    @Test("Owner switching can prune stale recurringTask hidden tag ids")
    func ownerSwitchingCanPruneStaleRecurringTaskSelectedTagIDs() {
        let storageURL = TestHelpers.makeTemporaryFileURL("owner-switch-recurringTask-list-preferences")
        let store = ListPreferencesStore(storageURL: storageURL, initialOwnerID: "user-a")

        store.toggleRecurringTaskTag("focus")
        store.setCurrentOwner("user-b")
        store.toggleRecurringTaskTag("stale")
        store.sanitizeRecurringTaskSelectedTags(validTagIDs: [])

        #expect(store.recurringTaskPreferences.hiddenTagIDs.isEmpty)

        store.setCurrentOwner("user-a")
        #expect(store.recurringTaskPreferences.hiddenTagIDs == ["focus"])
    }

    // Behaviour: status chips behave like tag chips: disabling one persists so
    // reopening the list keeps that class of entries hidden.
    @Test("Task status visibility toggles persist")
    func taskStatusVisibilityTogglesPersist() {
        let storageURL = TestHelpers.makeTemporaryFileURL("persisted-task-status-list-preferences")

        let firstStore = ListPreferencesStore(storageURL: storageURL)
        firstStore.toggleTaskStatus(.completed)
        firstStore.toggleTaskStatus(.hidden)

        let relaunchedStore = ListPreferencesStore(storageURL: storageURL)

        #expect(relaunchedStore.taskPreferences.hiddenStatusFilters == [.completed, .hidden])
    }

    // Behaviour: the Earn list keeps its combined task/recurringTask filter choices
    // separate from the narrower Tasks and RecurringTasks tabs.
    @Test("Earn list preferences persist independently")
    func earnPreferencesPersistIndependently() {
        let storageURL = TestHelpers.makeTemporaryFileURL("persisted-earn-list-preferences")
        let tagID: RecordID = "morning"

        let firstStore = ListPreferencesStore(storageURL: storageURL)
        firstStore.setEarnSort(.oldestToNewest)
        firstStore.toggleEarnStatus(.recurringTask)
        firstStore.toggleEarnTag(tagID)

        let relaunchedStore = ListPreferencesStore(storageURL: storageURL)

        #expect(relaunchedStore.earnPreferences.sort == .oldestToNewest)
        #expect(relaunchedStore.earnPreferences.hiddenStatusFilters == [.recurringTask])
        #expect(relaunchedStore.earnPreferences.hiddenTagIDs == [tagID])
        #expect(relaunchedStore.taskPreferences == EntityListPreferences())
        #expect(relaunchedStore.recurringTaskPreferences == EntityListPreferences())
    }

    // Behaviour: if the whole Task chip is off in Earn, tapping Complete only
    // brings tasks back; it should not secretly change the completion subfilter.
    @Test("Earn task completion toggles re-enable hidden task group")
    func earnTaskCompletionToggleReenablesHiddenTaskGroup() {
        var preferences = EntityListPreferences(hiddenStatusFilters: [.task, .completed])

        EarnListFilterSupport.toggleTaskCompletion(.completed, in: &preferences)

        #expect(preferences.showsStatus(.task))
        #expect(preferences.showsStatus(.completed) == false)
    }
}
