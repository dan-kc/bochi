import Foundation
import Testing
@testable import tofustash

@MainActor
struct EntityListQueryTests {

    // Behaviour: When the user filters habits to only those with a difficulty,
    // unranked habits should disappear from the list.
    @Test("Habit difficulty filter keeps only ranked habits")
    func habitDifficultyFilterKeepsRankedHabits() {
        let easy = makeHabit(id: "easy", createdAt: date(day: 1), frequency: 1, difficulty: .light)
        let unset = makeHabit(id: "unset", createdAt: date(day: 2), frequency: 1, difficulty: nil)

        var preferences = EntityListPreferences()
        preferences.difficultyFilter = .hasValue

        let visible = EntityListQuery.apply(
            items: [easy, unset],
            preferences: preferences,
            validTagIDs: [],
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { _ in nil },
            hasDifficulty: { $0.difficultyTier != nil },
            hasFrequency: { $0.frequency != nil },
            tags: { _ in [] }
        )

        #expect(visible.map(\.id) == [easy.id])
    }

    // Behaviour: When the user filters rewards to entries without a frequency cap,
    // only uncapped rewards remain visible.
    @Test("Reward frequency filter keeps only rewards without a frequency")
    func rewardFrequencyFilterKeepsMissingFrequencyRewards() {
        let uncapped = makeReward(id: "uncapped", createdAt: date(day: 1), maxFrequency: nil, damage: .heavy)
        let capped = makeReward(id: "capped", createdAt: date(day: 2), maxFrequency: 1, damage: .heavy)

        var preferences = EntityListPreferences()
        preferences.frequencyFilter = .missingValue

        let visible = EntityListQuery.apply(
            items: [capped, uncapped],
            preferences: preferences,
            validTagIDs: [],
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.damageTier?.sortOrder },
            price: { _ in nil },
            hasDifficulty: { $0.damageTier != nil },
            hasFrequency: { $0.maxFrequency != nil },
            tags: { _ in [] }
        )

        #expect(visible.map(\.id) == [uncapped.id])
    }

    // Behaviour: In "match any" mode, selecting multiple tags should widen the
    // list to anything matching at least one chosen tag.
    @Test("Tag any mode keeps items with at least one selected tag")
    func tagAnyModeMatchesAtLeastOneTag() {
        let social = makeTag(id: "social", name: "Social")
        let health = makeTag(id: "health", name: "Health")
        let callFriend = makeHabit(id: "call", createdAt: date(day: 1), frequency: 1, difficulty: .light)
        let pushups = makeHabit(id: "pushups", createdAt: date(day: 2), frequency: 1, difficulty: .hard)
        let reading = makeHabit(id: "read", createdAt: date(day: 3), frequency: 1, difficulty: .medium)
        let tagsByHabitID: [RecordID: [Tag]] = [
            callFriend.id: [social],
            pushups.id: [health],
            reading.id: []
        ]

        var preferences = EntityListPreferences()
        preferences.selectedTagIDs = [social.id, health.id]
        preferences.tagMatchMode = .any

        let visible = EntityListQuery.apply(
            items: [callFriend, pushups, reading],
            preferences: preferences,
            validTagIDs: [social.id, health.id],
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { _ in nil },
            hasDifficulty: { $0.difficultyTier != nil },
            hasFrequency: { $0.frequency != nil },
            tags: { tagsByHabitID[$0.id] ?? [] }
        )

        #expect(visible.map(\.id) == [callFriend.id, pushups.id])
    }

    // Behaviour: In "match all" mode, the user should only see entries that
    // contain every selected tag.
    @Test("Tag all mode keeps only items containing every selected tag")
    func tagAllModeRequiresEveryTag() {
        let social = makeTag(id: "social", name: "Social")
        let health = makeTag(id: "health", name: "Health")
        let both = makeReward(id: "both", createdAt: date(day: 1), maxFrequency: 1, damage: .medium)
        let one = makeReward(id: "one", createdAt: date(day: 2), maxFrequency: 1, damage: .medium)
        let tagsByRewardID: [RecordID: [Tag]] = [
            both.id: [social, health],
            one.id: [social]
        ]

        var preferences = EntityListPreferences()
        preferences.selectedTagIDs = [social.id, health.id]
        preferences.tagMatchMode = .all

        let visible = EntityListQuery.apply(
            items: [one, both],
            preferences: preferences,
            validTagIDs: [social.id, health.id],
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.damageTier?.sortOrder },
            price: { _ in nil },
            hasDifficulty: { $0.damageTier != nil },
            hasFrequency: { $0.maxFrequency != nil },
            tags: { tagsByRewardID[$0.id] ?? [] }
        )

        #expect(visible.map(\.id) == [both.id])
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
            preferences: EntityListPreferences(),
            validTagIDs: [],
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { prices[$0.id] },
            hasDifficulty: { $0.difficultyTier != nil },
            hasFrequency: { $0.frequency != nil },
            tags: { _ in [] }
        )

        #expect(visible.map(\.id) == [expensive.id, cheap.id, missingPrice.id])
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
            preferences: preferences,
            validTagIDs: [],
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { _ in nil },
            hasDifficulty: { $0.difficultyTier != nil },
            hasFrequency: { $0.frequency != nil },
            tags: { _ in [] }
        )

        #expect(visible.map(\.id) == [trivial.id, mediumOlder.id, mediumNewer.id, hard.id])
    }

    // Behaviour: If a saved filter references tags that are no longer available
    // on this list, the query should ignore those stale ids instead of hiding
    // every row until the store cleanup runs.
    @Test("Invalid selected tag ids are ignored by the query layer")
    func invalidSelectedTagsAreIgnored() {
        let focus = makeTag(id: "focus", name: "Focus")
        let stretch = makeHabit(id: "stretch", createdAt: date(day: 1), frequency: 1, difficulty: .light)
        let journal = makeHabit(id: "journal", createdAt: date(day: 2), frequency: 1, difficulty: .medium)
        let tagsByHabitID: [RecordID: [Tag]] = [
            stretch.id: [focus],
            journal.id: []
        ]

        var preferences = EntityListPreferences()
        preferences.selectedTagIDs = ["deleted-tag"]

        let visible = EntityListQuery.apply(
            items: [stretch, journal],
            preferences: preferences,
            validTagIDs: [focus.id],
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { _ in nil },
            hasDifficulty: { $0.difficultyTier != nil },
            hasFrequency: { $0.frequency != nil },
            tags: { tagsByHabitID[$0.id] ?? [] }
        )

        #expect(visible.map(\.id) == [stretch.id, journal.id])
    }

    // Behaviour: If a saved filter contains both current and stale tags, only the
    // tags still present on the list should affect which rows stay visible.
    @Test("Mixed valid and invalid selected tag ids only use the valid ids")
    func mixedValidAndInvalidSelectedTagsOnlyUseValidIDs() {
        let focus = makeTag(id: "focus", name: "Focus")
        let deepWork = makeHabit(id: "deep-work", createdAt: date(day: 1), frequency: 1, difficulty: .hard)
        let walk = makeHabit(id: "walk", createdAt: date(day: 2), frequency: 1, difficulty: .light)
        let tagsByHabitID: [RecordID: [Tag]] = [
            deepWork.id: [focus],
            walk.id: []
        ]

        var preferences = EntityListPreferences()
        preferences.selectedTagIDs = [focus.id, "deleted-tag"]
        preferences.tagMatchMode = .any

        let visible = EntityListQuery.apply(
            items: [walk, deepWork],
            preferences: preferences,
            validTagIDs: [focus.id],
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.difficultyTier?.sortOrder },
            price: { _ in nil },
            hasDifficulty: { $0.difficultyTier != nil },
            hasFrequency: { $0.frequency != nil },
            tags: { tagsByHabitID[$0.id] ?? [] }
        )

        #expect(visible.map(\.id) == [deepWork.id])
    }

    // Behaviour: "Match all" should still work after stale ids are stripped, so
    // a deleted tag does not make a still-valid AND filter impossible to satisfy.
    @Test("Tag all mode keeps working after invalid ids are removed")
    func tagAllModeStillWorksAfterInvalidIDsAreRemoved() {
        let focus = makeTag(id: "focus", name: "Focus")
        let calm = makeTag(id: "calm", name: "Calm")
        let tea = makeReward(id: "tea", createdAt: date(day: 1), maxFrequency: 1, damage: .light)
        let nap = makeReward(id: "nap", createdAt: date(day: 2), maxFrequency: 1, damage: .medium)
        let tagsByRewardID: [RecordID: [Tag]] = [
            tea.id: [focus, calm],
            nap.id: [focus]
        ]

        var preferences = EntityListPreferences()
        preferences.selectedTagIDs = [focus.id, calm.id, "deleted-tag"]
        preferences.tagMatchMode = .all

        let visible = EntityListQuery.apply(
            items: [tea, nap],
            preferences: preferences,
            validTagIDs: [focus.id, calm.id],
            id: \.id,
            createdAt: \.createdAt,
            difficultySortOrder: { $0.damageTier?.sortOrder },
            price: { _ in nil },
            hasDifficulty: { $0.damageTier != nil },
            hasFrequency: { $0.maxFrequency != nil },
            tags: { tagsByRewardID[$0.id] ?? [] }
        )

        #expect(visible.map(\.id) == [tea.id])
    }

    private func date(day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day * 86_400))
    }

    private func makeHabit(
        id: RecordID,
        createdAt: Date,
        frequency: Double?,
        difficulty: HabitDifficultyTier?
    ) -> Habit {
        Habit(
            id: id,
            name: id.rawValue,
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            frequency: frequency,
            difficultyTier: difficulty
        )
    }

    private func makeReward(
        id: RecordID,
        createdAt: Date,
        maxFrequency: Double?,
        damage: RewardDamageTier?
    ) -> Reward {
        Reward(
            id: id,
            name: id.rawValue,
            description: "",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            maxFrequency: maxFrequency,
            damageTier: damage
        )
    }

    private func makeTag(id: RecordID, name: String) -> Tag {
        let createdAt = date(day: 1)
        return Tag(
            id: id,
            name: name,
            colorHex: "#ffffff",
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }
}
