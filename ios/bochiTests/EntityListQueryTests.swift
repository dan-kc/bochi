import Foundation
import Testing
@testable import bochi

@MainActor
struct EntityListQueryTests {
    // Behaviour: Turning off tag chips should hide rows that carry any disabled
    // tag while leaving untagged rows visible.
    @Test("Hidden tags remove rows carrying those tags")
    func hiddenTagsRemoveRowsCarryingThoseTags() {
        let social = makeTag(id: "social", name: "Social")
        let health = makeTag(id: "health", name: "Health")
        let callFriend = makeRecurringTask(id: "call", createdAt: date(day: 1), frequency: 1)
        let pushups = makeRecurringTask(id: "pushups", createdAt: date(day: 2), frequency: 1)
        let reading = makeRecurringTask(id: "read", createdAt: date(day: 3), frequency: 1)
        let tagsByRecurringTaskID: [RecordID: [bochi.Tag]] = [
            callFriend.id: [social],
            pushups.id: [health],
            reading.id: []
        ]

        var preferences = EntityListPreferences()
        preferences.hiddenTagIDs = [social.id, health.id]

        let visible = EntityListQuery.apply(
            items: [callFriend, pushups, reading],
            preferences: preferences,
            validTagIDs: [social.id, health.id],
            id: \.id,
            createdAt: \.createdAt,
            price: { _ in nil },
            tags: { tagsByRecurringTaskID[$0.id] ?? [] }
        )

        #expect(visible.map { $0.id } == [reading.id])
    }

    // Behaviour: Since every tag chip starts enabled, an untouched list should
    // show tagged and untagged rows together.
    @Test("No hidden tags leaves the full list visible")
    func noHiddenTagsLeavesListVisible() {
        let focus = makeTag(id: "focus", name: "Focus")
        let stretch = makeRecurringTask(id: "stretch", createdAt: date(day: 1), frequency: 1)
        let journal = makeRecurringTask(id: "journal", createdAt: date(day: 2), frequency: 1)
        let tagsByRecurringTaskID: [RecordID: [bochi.Tag]] = [
            stretch.id: [focus],
            journal.id: []
        ]

        let visible = EntityListQuery.apply(
            items: [journal, stretch],
            preferences: EntityListPreferences(),
            validTagIDs: [focus.id],
            id: \.id,
            createdAt: \.createdAt,
            price: { _ in nil },
            tags: { tagsByRecurringTaskID[$0.id] ?? [] }
        )

        #expect(visible.map { $0.id } == [stretch.id, journal.id])
    }

    // Behaviour: Price descending is the default list view, so the most
    // valuable tradable item should appear first when the app opens.
    @Test("Default sort orders items by price descending and leaves missing prices last")
    func defaultSortUsesPriceDescending() {
        let expensive = makeRecurringTask(id: "expensive", createdAt: date(day: 1), frequency: 1)
        let cheap = makeRecurringTask(id: "cheap", createdAt: date(day: 2), frequency: 1)
        let missingPrice = makeRecurringTask(id: "missing", createdAt: date(day: 3), frequency: nil)
        let prices: [RecordID: Int] = [
            expensive.id: 20,
            cheap.id: 5
        ]

        let visible = EntityListQuery.apply(
            items: [cheap, missingPrice, expensive],
            preferences: EntityListPreferences(),
            validTagIDs: [],
            id: \.id,
            createdAt: \.createdAt,
            price: { prices[$0.id] },
            tags: { _ in [] }
        )

        #expect(visible.map { $0.id } == [expensive.id, cheap.id, missingPrice.id])
    }

    // Behaviour: free users should always see the default value-first ordering,
    // even when a saved premium sort preference exists from an earlier session.
    @Test("Free access ignores saved premium sorts and uses price descending")
    func freeAccessIgnoresSavedPremiumSortsAndUsesPriceDescending() {
        let oldCheap = makeRecurringTask(id: "old-cheap", createdAt: date(day: 1), frequency: 1)
        let newExpensive = makeRecurringTask(id: "new-expensive", createdAt: date(day: 2), frequency: 1)
        let prices: [RecordID: Int] = [
            oldCheap.id: 5,
            newExpensive.id: 20
        ]

        var preferences = EntityListPreferences()
        preferences.sort = .oldestToNewest

        let visible = EntityListQuery.apply(
            items: [oldCheap, newExpensive],
            preferences: preferences,
            hasPremiumAccess: false,
            validTagIDs: [],
            id: \.id,
            createdAt: \.createdAt,
            price: { prices[$0.id] },
            tags: { _ in [] }
        )

        #expect(visible.map { $0.id } == [newExpensive.id, oldCheap.id])
    }

    // Behaviour: premium users keep control over the saved sort preference.
    @Test("Premium access keeps the selected sort")
    func premiumAccessKeepsSelectedSort() {
        let oldCheap = makeRecurringTask(id: "old-cheap", createdAt: date(day: 1), frequency: 1)
        let newExpensive = makeRecurringTask(id: "new-expensive", createdAt: date(day: 2), frequency: 1)
        let prices: [RecordID: Int] = [
            oldCheap.id: 5,
            newExpensive.id: 20
        ]

        var preferences = EntityListPreferences()
        preferences.sort = .oldestToNewest

        let visible = EntityListQuery.apply(
            items: [newExpensive, oldCheap],
            preferences: preferences,
            hasPremiumAccess: true,
            validTagIDs: [],
            id: \.id,
            createdAt: \.createdAt,
            price: { prices[$0.id] },
            tags: { _ in [] }
        )

        #expect(visible.map { $0.id } == [oldCheap.id, newExpensive.id])
    }

    // Behaviour: blocked tasks should always sink below actionable tasks,
    // regardless of the active sort option, so the user sees work they can do first.
    @Test("Blocked items are always sorted after unblocked items")
    func blockedItemsAlwaysSortAfterUnblockedItems() {
        let highValueBlocked = makeTask(id: "blocked", createdAt: date(day: 1))
        let lowValueOpen = makeTask(id: "open", createdAt: date(day: 2))
        let prices: [RecordID: Int] = [
            highValueBlocked.id: 20,
            lowValueOpen.id: 5
        ]

        let visible = EntityListQuery.apply(
            items: [highValueBlocked, lowValueOpen],
            preferences: EntityListPreferences(),
            validTagIDs: [],
            id: \.id,
            createdAt: \.createdAt,
            price: { prices[$0.id] },
            tags: { _ in [] },
            isDeprioritized: { $0.id == highValueBlocked.id }
        )

        #expect(visible.map { $0.id } == [lowValueOpen.id, highValueBlocked.id])
    }

    // Behaviour: pinned rows should stay above ordinary rows while still
    // respecting the user's selected sort inside the pinned group.
    @Test("Pinned items sort before unpinned items")
    func pinnedItemsSortBeforeUnpinnedItems() {
        let highValueUnpinned = makeRecurringTask(id: "expensive", createdAt: date(day: 1), frequency: 1)
        let lowValuePinned = makeRecurringTask(id: "pinned", createdAt: date(day: 2), frequency: 1, pinned: true)
        let prices: [RecordID: Int] = [
            highValueUnpinned.id: 20,
            lowValuePinned.id: 5
        ]

        let visible = EntityListQuery.apply(
            items: [highValueUnpinned, lowValuePinned],
            preferences: EntityListPreferences(),
            validTagIDs: [],
            id: \.id,
            createdAt: \.createdAt,
            price: { prices[$0.id] },
            tags: { _ in [] },
            isPinned: \.pinned
        )

        #expect(visible.map { $0.id } == [lowValuePinned.id, highValueUnpinned.id])
    }

    // Behaviour: Price ascending should use creation date as a stable tie breaker.
    @Test("Price ascending uses date tie breaker")
    func priceAscendingUsesDateTieBreaker() {
        let older = makeRecurringTask(id: "older", createdAt: date(day: 1), frequency: 1)
        let newer = makeRecurringTask(id: "newer", createdAt: date(day: 2), frequency: 1)
        var preferences = EntityListPreferences()
        preferences.sort = .priceLowToHigh

        let visible = EntityListQuery.apply(
            items: [newer, older],
            preferences: preferences,
            validTagIDs: [],
            id: \.id,
            createdAt: \.createdAt,
            price: { _ in 10 },
            tags: { _ in [] }
        )

        #expect(visible.map { $0.id } == [older.id, newer.id])
    }

    // Behaviour: If a saved filter references tags that are no longer available
    // for the current owner, the query should ignore those stale ids.
    @Test("Invalid hidden tag ids are ignored by the query layer")
    func invalidSelectedTagsAreIgnored() {
        let focus = makeTag(id: "focus", name: "Focus")
        let stretch = makeRecurringTask(id: "stretch", createdAt: date(day: 1), frequency: 1)
        let journal = makeRecurringTask(id: "journal", createdAt: date(day: 2), frequency: 1)
        let tagsByRecurringTaskID: [RecordID: [bochi.Tag]] = [
            stretch.id: [focus],
            journal.id: []
        ]

        var preferences = EntityListPreferences()
        preferences.hiddenTagIDs = ["deleted-tag"]

        let visible = EntityListQuery.apply(
            items: [stretch, journal],
            preferences: preferences,
            validTagIDs: [focus.id],
            id: \.id,
            createdAt: \.createdAt,
            price: { _ in nil },
            tags: { tagsByRecurringTaskID[$0.id] ?? [] }
        )

        #expect(visible.map { $0.id } == [stretch.id, journal.id])
    }

    // Behaviour: If a saved filter contains both current and stale tags, only the
    // tags still present for the current owner should affect which rows stay visible.
    @Test("Mixed valid and invalid hidden tag ids only use the valid ids")
    func mixedValidAndInvalidSelectedTagsOnlyUseValidIDs() {
        let focus = makeTag(id: "focus", name: "Focus")
        let deepWork = makeRecurringTask(id: "deep-work", createdAt: date(day: 1), frequency: 1)
        let walk = makeRecurringTask(id: "walk", createdAt: date(day: 2), frequency: 1)
        let tagsByRecurringTaskID: [RecordID: [bochi.Tag]] = [
            deepWork.id: [focus],
            walk.id: []
        ]

        var preferences = EntityListPreferences()
        preferences.hiddenTagIDs = [focus.id, "deleted-tag"]

        let visible = EntityListQuery.apply(
            items: [walk, deepWork],
            preferences: preferences,
            validTagIDs: [focus.id],
            id: \.id,
            createdAt: \.createdAt,
            price: { _ in nil },
            tags: { tagsByRecurringTaskID[$0.id] ?? [] }
        )

        #expect(visible.map { $0.id } == [walk.id])
    }

    // Behaviour: Status visibility chips should hide every row that belongs to
    // a disabled state before sort order is considered.
    @Test("Hidden status filters remove matching rows")
    func hiddenStatusFiltersRemoveMatchingRows() {
        let openTask = makeTask(id: "open", createdAt: date(day: 1))
        let completedTask = makeTask(id: "completed", createdAt: date(day: 2))

        var preferences = EntityListPreferences()
        preferences.hiddenStatusFilters = [.completed]

        let visible = EntityListQuery.apply(
            items: [completedTask, openTask],
            preferences: preferences,
            validTagIDs: [],
            id: \.id,
            createdAt: \.createdAt,
            price: { _ in nil },
            tags: { _ in [] },
            statuses: { task in
                task.id == completedTask.id ? [.completed] : [.incomplete]
            }
        )

        #expect(visible.map { $0.id } == [openTask.id])
    }

    private func date(day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86_400))
    }

    private func makeRecurringTask(
        id: RecordID,
        createdAt: Date,
        frequency: Double?,
        description: String = "",
        pinned: Bool = false
    ) -> RecurringTask {
        RecurringTask(
            id: id,
            name: id.rawValue,
            description: description,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            frequency: frequency,
            basePrice: 100,
            pinned: pinned
        )
    }

    private func makeTask(
        id: RecordID,
        createdAt: Date
    ) -> TaskItem {
        TaskItem(
            id: id,
            name: id.rawValue,
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            basePrice: 200,
            dueDate: nil
        )
    }

    private func makeTag(id: RecordID, name: String) -> bochi.Tag {
        let createdAt = date(day: 1)
        return bochi.Tag(
            id: id,
            name: name,
            colorHex: "#336699",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }
}
