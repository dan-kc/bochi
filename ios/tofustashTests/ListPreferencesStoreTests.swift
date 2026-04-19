import Testing
@testable import tofustash

@MainActor
struct ListPreferencesStoreTests {

    // Behaviour: After the user customizes the habits list, the app should reopen
    // with the same sort, field filters, and selected tags still active.
    @Test("Habit list preferences persist across store relaunch")
    func habitPreferencesPersistAcrossRelaunch() {
        let storageURL = TestHelpers.makeTemporaryFileURL("persisted-habit-list-preferences")
        let tagID: RecordID = "focus"

        let firstStore = ListPreferencesStore(storageURL: storageURL)
        firstStore.setHabitSort(.difficultyLowToHigh)
        firstStore.setHabitDifficultyFilter(.hasValue)
        firstStore.setHabitFrequencyFilter(.missingValue)
        firstStore.setHabitTagMatchMode(.all)
        firstStore.toggleHabitTag(tagID)

        let relaunchedStore = ListPreferencesStore(storageURL: storageURL)

        #expect(relaunchedStore.habitPreferences.sort == .difficultyLowToHigh)
        #expect(relaunchedStore.habitPreferences.difficultyFilter == .hasValue)
        #expect(relaunchedStore.habitPreferences.frequencyFilter == .missingValue)
        #expect(relaunchedStore.habitPreferences.tagMatchMode == .all)
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
        firstStore.setRewardDifficultyFilter(.missingValue)
        firstStore.setRewardFrequencyFilter(.hasValue)
        firstStore.setRewardTagMatchMode(.any)
        firstStore.toggleRewardTag(rewardTagID)

        let relaunchedStore = ListPreferencesStore(storageURL: storageURL)

        #expect(relaunchedStore.rewardPreferences.sort == .oldestToNewest)
        #expect(relaunchedStore.rewardPreferences.difficultyFilter == .missingValue)
        #expect(relaunchedStore.rewardPreferences.frequencyFilter == .hasValue)
        #expect(relaunchedStore.rewardPreferences.tagMatchMode == .any)
        #expect(relaunchedStore.rewardPreferences.selectedTagIDs == [rewardTagID])
        #expect(relaunchedStore.habitPreferences == EntityListPreferences())
    }
}
