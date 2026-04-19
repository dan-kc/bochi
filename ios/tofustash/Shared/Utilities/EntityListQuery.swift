import Foundation

enum EntityListQuery {
    // Shared selector for both screens: filter first, then sort the visible
    // snapshot. In React terms, this is the memoized derived list both tabs can
    // reuse instead of each screen hand-rolling the same pipeline.
    static func apply<Item>(
        items: [Item],
        preferences: EntityListPreferences,
        id: (Item) -> RecordID,
        createdAt: (Item) -> Date,
        difficultySortOrder: (Item) -> Int?,
        price: (Item) -> Int?,
        hasDifficulty: (Item) -> Bool,
        hasFrequency: (Item) -> Bool,
        tags: (Item) -> [Tag]
    ) -> [Item] {
        let filteredItems = items.filter { item in
            matches(preferences.difficultyFilter, hasValue: hasDifficulty(item))
                && matches(preferences.frequencyFilter, hasValue: hasFrequency(item))
                && matchesTagFilter(
                    selectedTagIDs: preferences.selectedTagIDs,
                    matchMode: preferences.tagMatchMode,
                    itemTags: tags(item)
                )
        }

        return filteredItems.sorted { lhs, rhs in
            compare(
                lhs,
                rhs,
                sort: preferences.sort,
                id: id,
                createdAt: createdAt,
                difficultySortOrder: difficultySortOrder,
                price: price
            )
        }
    }

    private static func matches(_ filter: EntityListOptionalFieldFilter, hasValue: Bool) -> Bool {
        switch filter {
        case .any:
            true
        case .hasValue:
            hasValue
        case .missingValue:
            !hasValue
        }
    }

    private static func matchesTagFilter(
        selectedTagIDs: [RecordID],
        matchMode: EntityListTagMatchMode,
        itemTags: [Tag]
    ) -> Bool {
        guard !selectedTagIDs.isEmpty else { return true }

        let itemTagIDs = Set(itemTags.map(\.id))

        switch matchMode {
        case .any:
            // Behaviour: "match any" should widen the result set to anything that
            // shares at least one chosen tag.
            return selectedTagIDs.contains { itemTagIDs.contains($0) }
        case .all:
            // Behaviour: "match all" should act like an AND query so only items
            // carrying every selected tag remain visible.
            return selectedTagIDs.allSatisfy { itemTagIDs.contains($0) }
        }
    }

    private static func compare<Item>(
        _ lhs: Item,
        _ rhs: Item,
        sort: EntityListSortOption,
        id: (Item) -> RecordID,
        createdAt: (Item) -> Date,
        difficultySortOrder: (Item) -> Int?,
        price: (Item) -> Int?
    ) -> Bool {
        switch sort {
        case .oldestToNewest:
            return compareDates(createdAt(lhs), createdAt(rhs), lhsID: id(lhs), rhsID: id(rhs), newerFirst: false)
        case .newestToOldest:
            return compareDates(createdAt(lhs), createdAt(rhs), lhsID: id(lhs), rhsID: id(rhs), newerFirst: true)
        case .difficultyLowToHigh:
            return compareOptionalInts(
                difficultySortOrder(lhs),
                difficultySortOrder(rhs),
                lhsDate: createdAt(lhs),
                rhsDate: createdAt(rhs),
                lhsID: id(lhs),
                rhsID: id(rhs),
                descending: false
            )
        case .difficultyHighToLow:
            return compareOptionalInts(
                difficultySortOrder(lhs),
                difficultySortOrder(rhs),
                lhsDate: createdAt(lhs),
                rhsDate: createdAt(rhs),
                lhsID: id(lhs),
                rhsID: id(rhs),
                descending: true
            )
        case .priceLowToHigh:
            return compareOptionalInts(
                price(lhs),
                price(rhs),
                lhsDate: createdAt(lhs),
                rhsDate: createdAt(rhs),
                lhsID: id(lhs),
                rhsID: id(rhs),
                descending: false
            )
        case .priceHighToLow:
            return compareOptionalInts(
                price(lhs),
                price(rhs),
                lhsDate: createdAt(lhs),
                rhsDate: createdAt(rhs),
                lhsID: id(lhs),
                rhsID: id(rhs),
                descending: true
            )
        }
    }

    private static func compareDates(
        _ lhs: Date,
        _ rhs: Date,
        lhsID: RecordID,
        rhsID: RecordID,
        newerFirst: Bool
    ) -> Bool {
        if lhs != rhs {
            return newerFirst ? lhs > rhs : lhs < rhs
        }

        return lhsID.rawValue < rhsID.rawValue
    }

    private static func compareOptionalInts(
        _ lhs: Int?,
        _ rhs: Int?,
        lhsDate: Date,
        rhsDate: Date,
        lhsID: RecordID,
        rhsID: RecordID,
        descending: Bool
    ) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?):
            if left != right {
                return descending ? left > right : left < right
            }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }

        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }

        return lhsID.rawValue < rhsID.rawValue
    }
}
