import Foundation

enum EntityListQuery {
    // Shared selector for both screens: filter first, then sort the visible
    // snapshot. In React terms, this is the memoized derived list both tabs can
    // reuse instead of each screen hand-rolling the same pipeline.
    static func apply<Item>(
        items: [Item],
        filterState: EntityListFilterState,
        validTagIDs: Set<RecordID>,
        id: (Item) -> RecordID,
        name: (Item) -> String,
        createdAt: (Item) -> Date,
        difficultySortOrder: (Item) -> Int?,
        price: (Item) -> Int?,
        tags: (Item) -> [Tag],
        isDeprioritized: (Item) -> Bool = { _ in false }
    ) -> [Item] {
        let selectedTagIDs = filterState.preferences.selectedTagIDs.filter { validTagIDs.contains($0) }
        let trimmedSearchText = filterState.search.trimmedText

        let filteredItems = items.filter { item in
            matchesTagFilter(
                selectedTagIDs: selectedTagIDs,
                itemTags: tags(item)
            )
                && matchesNameFilter(
                    searchText: trimmedSearchText,
                    name: name(item)
                )
        }

        return filteredItems.sorted { lhs, rhs in
            let lhsIsDeprioritized = isDeprioritized(lhs)
            let rhsIsDeprioritized = isDeprioritized(rhs)
            if lhsIsDeprioritized != rhsIsDeprioritized {
                return !lhsIsDeprioritized
            }

            return compare(
                lhs,
                rhs,
                sort: filterState.preferences.sort,
                id: id,
                createdAt: createdAt,
                difficultySortOrder: difficultySortOrder,
                price: price
            )
        }
    }

    private static func matchesNameFilter(
        searchText: String,
        name: String
    ) -> Bool {
        guard !searchText.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(searchText)
    }

    private static func matchesTagFilter(
        selectedTagIDs: [RecordID],
        itemTags: [Tag]
    ) -> Bool {
        guard !selectedTagIDs.isEmpty else { return true }

        let itemTagIDs = Set(itemTags.map(\.id))
        // Behaviour: selecting multiple tags should widen the result set to
        // anything that shares at least one chosen tag.
        return selectedTagIDs.contains { itemTagIDs.contains($0) }
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
