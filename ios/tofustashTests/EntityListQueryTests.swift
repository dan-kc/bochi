import Foundation
import Testing
@testable import tofustash

@MainActor
struct EntityListQueryTests {

    // Behaviour: In "match any" mode, selecting multiple tags should widen the
    // list to anything matching at least one chosen tag.
    @Test("Selecting multiple tags keeps items with at least one selected tag")
    func selectedTagsMatchAtLeastOneTag() {
        let social = makeTag(id: "social", name: "Social")
        let health = makeTag(id: "health", name: "Health")
        let callFriend = makeHabit(id: "call", createdAt: date(day: 1), frequency: 1, difficulty: .light)
        let pushups = makeHabit(id: "pushups", createdAt: date(day: 2), frequency: 1, difficulty: .hard)
        let reading = makeHabit(id: "read", createdAt: date(day: 3), frequency: 1, difficulty: .medium)
        let tagsByHabitID: [RecordID: [tofustash.Tag]] = [
            callFriend.id: [social],
            pushups.id: [health],
            reading.id: []
        ]

        var preferences = EntityListPreferences()
        preferences.selectedTagIDs = [social.id, health.id]

        let visible = EntityListQuery.apply(
            items: [callFriend, pushups, reading],
            filterState: EntityListFilterState(
                preferences: preferences,
                search: EntityListSearchState()
            ),
            validTagIDs: [social.id, health.id],
            id: \.id,
            name: \.name,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { _ in nil },
            tags: { tagsByHabitID[$0.id] ?? [] }
        )

        #expect(visible.map(\.id) == [callFriend.id, pushups.id])
    }

    // Behaviour: When no tags are selected, the user should see the full list
    // and the tag controls should effectively read as "All".
    @Test("No selected tags leaves the full list visible")
    func noSelectedTagsLeavesListVisible() {
        let focus = makeTag(id: "focus", name: "Focus")
        let stretch = makeHabit(id: "stretch", createdAt: date(day: 1), frequency: 1, difficulty: .light)
        let journal = makeHabit(id: "journal", createdAt: date(day: 2), frequency: 1, difficulty: .medium)
        let tagsByHabitID: [RecordID: [tofustash.Tag]] = [
            stretch.id: [focus],
            journal.id: []
        ]

        let visible = EntityListQuery.apply(
            items: [journal, stretch],
            filterState: EntityListFilterState(
                preferences: EntityListPreferences(),
                search: EntityListSearchState()
            ),
            validTagIDs: [focus.id],
            id: \.id,
            name: \.name,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { _ in nil },
            tags: { tagsByHabitID[$0.id] ?? [] }
        )

        #expect(visible.map(\.id) == [stretch.id, journal.id])
    }

    // Behaviour: Price descending is the default list view, so the most
    // valuable tradable habit should appear first when the app opens.
    @Test("Default sort orders items by price descending and leaves missing prices last")
    func defaultSortUsesPriceDescending() {
        let expensive = makeHabit(id: "expensive", createdAt: date(day: 1), frequency: 1, difficulty: .hard)
        let cheap = makeHabit(id: "cheap", createdAt: date(day: 2), frequency: 1, difficulty: .light)
        let missingPrice = makeHabit(id: "missing", createdAt: date(day: 3), frequency: nil, difficulty: .medium)
        let prices: [RecordID: Int] = [
            expensive.id: 20,
            cheap.id: 5
        ]

        let visible = EntityListQuery.apply(
            items: [cheap, missingPrice, expensive],
            filterState: EntityListFilterState(
                preferences: EntityListPreferences(),
                search: EntityListSearchState()
            ),
            validTagIDs: [],
            id: \.id,
            name: \.name,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { prices[$0.id] },
            tags: { _ in [] }
        )

        #expect(visible.map(\.id) == [expensive.id, cheap.id, missingPrice.id])
    }

    // Behaviour: blocked tasks should always sink below actionable tasks,
    // regardless of the active sort option, so the user sees work they can do first.
    @Test("Blocked items are always sorted after unblocked items")
    func blockedItemsAlwaysSortAfterUnblockedItems() {
        let highValueBlocked = makeTask(id: "blocked", createdAt: date(day: 1), difficulty: .hard)
        let lowValueOpen = makeTask(id: "open", createdAt: date(day: 2), difficulty: .light)
        let prices: [RecordID: Int] = [
            highValueBlocked.id: 20,
            lowValueOpen.id: 5
        ]

        let visible = EntityListQuery.apply(
            items: [highValueBlocked, lowValueOpen],
            filterState: EntityListFilterState(
                preferences: EntityListPreferences(),
                search: EntityListSearchState()
            ),
            validTagIDs: [],
            id: \.id,
            name: \.name,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { prices[$0.id] },
            tags: { _ in [] },
            isDeprioritized: { $0.id == highValueBlocked.id }
        )

        #expect(visible.map(\.id) == [lowValueOpen.id, highValueBlocked.id])
    }

    // Behaviour: Difficulty sorts should respect the explicit tier order rather
    // than the row creation date or enum case declaration order by accident.
    @Test("Difficulty ascending uses tier sort order with a stable tie breaker")
    func difficultyAscendingUsesTierSortOrder() {
        let trivial = makeHabit(id: "trivial", createdAt: date(day: 2), frequency: 1, difficulty: .trivial)
        let mediumOlder = makeHabit(id: "medium-older", createdAt: date(day: 1), frequency: 1, difficulty: .medium)
        let mediumNewer = makeHabit(id: "medium-newer", createdAt: date(day: 3), frequency: 1, difficulty: .medium)
        let hard = makeHabit(id: "hard", createdAt: date(day: 4), frequency: 1, difficulty: .hard)

        var preferences = EntityListPreferences()
        preferences.sort = .difficultyLowToHigh

        let visible = EntityListQuery.apply(
            items: [hard, mediumNewer, trivial, mediumOlder],
            filterState: EntityListFilterState(
                preferences: preferences,
                search: EntityListSearchState()
            ),
            validTagIDs: [],
            id: \.id,
            name: \.name,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { _ in nil },
            tags: { _ in [] }
        )

        #expect(visible.map(\.id) == [trivial.id, mediumOlder.id, mediumNewer.id, hard.id])
    }

    // Behaviour: If a saved filter references tags that are no longer available
    // for the current owner, the query should ignore those stale ids instead of
    // hiding every row until the store cleanup runs.
    @Test("Invalid selected tag ids are ignored by the query layer")
    func invalidSelectedTagsAreIgnored() {
        let focus = makeTag(id: "focus", name: "Focus")
        let stretch = makeHabit(id: "stretch", createdAt: date(day: 1), frequency: 1, difficulty: .light)
        let journal = makeHabit(id: "journal", createdAt: date(day: 2), frequency: 1, difficulty: .medium)
        let tagsByHabitID: [RecordID: [tofustash.Tag]] = [
            stretch.id: [focus],
            journal.id: []
        ]

        var preferences = EntityListPreferences()
        preferences.selectedTagIDs = ["deleted-tag"]

        let visible = EntityListQuery.apply(
            items: [stretch, journal],
            filterState: EntityListFilterState(
                preferences: preferences,
                search: EntityListSearchState()
            ),
            validTagIDs: [focus.id],
            id: \.id,
            name: \.name,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { _ in nil },
            tags: { tagsByHabitID[$0.id] ?? [] }
        )

        #expect(visible.map(\.id) == [stretch.id, journal.id])
    }

    // Behaviour: If a saved filter contains both current and stale tags, only the
    // tags still present for the current owner should affect which rows stay visible.
    @Test("Mixed valid and invalid selected tag ids only use the valid ids")
    func mixedValidAndInvalidSelectedTagsOnlyUseValidIDs() {
        let focus = makeTag(id: "focus", name: "Focus")
        let deepWork = makeHabit(id: "deep-work", createdAt: date(day: 1), frequency: 1, difficulty: .hard)
        let walk = makeHabit(id: "walk", createdAt: date(day: 2), frequency: 1, difficulty: .light)
        let tagsByHabitID: [RecordID: [tofustash.Tag]] = [
            deepWork.id: [focus],
            walk.id: []
        ]

        var preferences = EntityListPreferences()
        preferences.selectedTagIDs = [focus.id, "deleted-tag"]

        let visible = EntityListQuery.apply(
            items: [walk, deepWork],
            filterState: EntityListFilterState(
                preferences: preferences,
                search: EntityListSearchState()
            ),
            validTagIDs: [focus.id],
            id: \.id,
            name: \.name,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { _ in nil },
            tags: { tagsByHabitID[$0.id] ?? [] }
        )

        #expect(visible.map(\.id) == [deepWork.id])
    }

    // Behaviour: list search should only match the visible entity name, so a
    // query never keeps a row around because the description happened to match.
    @Test("Name search is case-insensitive, trims whitespace, and ignores descriptions")
    func nameSearchMatchesNameOnly() {
        let bedtimeReading = makeHabit(
            id: "bedtime-reading",
            createdAt: date(day: 1),
            frequency: 1,
            difficulty: .light,
            description: "Wind down before bed"
        )
        let eveningWalk = makeHabit(
            id: "evening-walk",
            createdAt: date(day: 2),
            frequency: 1,
            difficulty: .medium,
            description: "Fresh air"
        )

        let visible = EntityListQuery.apply(
            items: [bedtimeReading, eveningWalk],
            filterState: EntityListFilterState(
                preferences: EntityListPreferences(),
                search: EntityListSearchState(text: "  WALK  ", isPresented: true)
            ),
            validTagIDs: [],
            id: \.id,
            name: \.name,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { _ in nil },
            tags: { _ in [] }
        )

        #expect(visible.map(\.id) == [eveningWalk.id])
    }

    private func date(day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86_400))
    }

    private func makeHabit(
        id: RecordID,
        createdAt: Date,
        frequency: Double?,
        difficulty: HabitDifficultyTier?,
        description: String = ""
    ) -> Habit {
        Habit(
            id: id,
            name: id.rawValue,
            description: description,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            frequency: frequency,
            difficultyTier: difficulty
        )
    }

    private func makeTask(
        id: RecordID,
        createdAt: Date,
        difficulty: HabitDifficultyTier?
    ) -> TaskItem {
        TaskItem(
            id: id,
            name: id.rawValue,
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            completedAt: nil,
            difficultyTier: difficulty,
            durationSeconds: nil,
            commitment: nil,
            dueDate: nil
        )
    }

    private func makeTag(id: RecordID, name: String) -> tofustash.Tag {
        let createdAt = date(day: 1)
        return tofustash.Tag(
            id: id,
            name: name,
            colorHex: "#ffffff",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }
}
