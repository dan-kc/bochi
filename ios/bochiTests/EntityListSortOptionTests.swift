import Testing
@testable import bochi

struct EntityListSortOptionTests {
    // Behaviour: sort menus should expose only price and creation-date sorts
    // after difficulty and damage sorting were removed.
    @Test("Only price and created-date sorts remain")
    func onlyPriceAndCreatedDateSortsRemain() {
        #expect(EntityListSortOption.allCases == [
            .oldestToNewest,
            .newestToOldest,
            .priceLowToHigh,
            .priceHighToLow
        ])
    }

    // Behaviour: sort labels should no longer vary between earning and reward
    // lists because damage terminology has been removed.
    @Test("Sort labels ignore damage terminology")
    func sortLabelsIgnoreDamageTerminology() {
        #expect(EntityListSortOption.priceLowToHigh.label(usesDamageTerminology: true) == "Price ascending")
        #expect(EntityListSortOption.priceLowToHigh.fieldLabel(usesDamageTerminology: true) == "Price")
        #expect(EntityListSortOption.priceLowToHigh.menuFieldLabel(usesDamageTerminology: true) == "Price")
        #expect(EntityListSortOption.oldestToNewest.label(usesDamageTerminology: true) == "Date created ascending")
    }

    // Behaviour: free users get the default value-first order; every custom
    // sort choice should be marked as premium-only before the UI renders it.
    @Test("All non-default sort options are premium-only")
    func allNonDefaultSortOptionsArePremiumOnly() {
        #expect(EntityListSortOption.priceHighToLow.isPremiumOnly == false)

        let premiumOptions = EntityListSortOption.allCases.filter(\.isPremiumOnly)

        #expect(premiumOptions == [
            .oldestToNewest,
            .newestToOldest,
            .priceLowToHigh
        ])
    }

    // Behaviour: when a user loses premium, stale custom sort preferences should
    // render and behave as Price descending without deleting the saved choice.
    @Test("Free access presents stale premium sort preferences as price descending")
    func freeAccessPresentsStalePremiumSortPreferencesAsPriceDescending() {
        var preferences = EntityListPreferences()
        preferences.sort = .oldestToNewest

        #expect(preferences.effectiveSort(hasPremiumAccess: false) == .priceHighToLow)
        #expect(preferences.sort == .oldestToNewest)
    }

    // Behaviour: premium users should still see the exact saved sort as active.
    @Test("Premium access presents the saved sort preference")
    func premiumAccessPresentsSavedSortPreference() {
        var preferences = EntityListPreferences()
        preferences.sort = .priceLowToHigh

        #expect(preferences.effectiveSort(hasPremiumAccess: true) == .priceLowToHigh)
    }
}
