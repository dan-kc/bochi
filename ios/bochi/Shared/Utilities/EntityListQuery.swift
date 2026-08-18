import Foundation

nonisolated enum EntityListQuery {
    // Shared selector for both screens: filter first, then sort the visible
    // snapshot. In React terms, this is the memoized derived list both tabs can
    // reuse instead of each screen hand-rolling the same pipeline.
    static func apply<Item>(
        items: [Item],
        preferences: EntityListPreferences,
        hasPremiumAccess: Bool = true,
        validTagIDs: Set<RecordID>,
        id: (Item) -> RecordID,
        createdAt: (Item) -> Date,
        price: (Item) -> Int?,
        tags: (Item) -> [Tag],
        statuses: (Item) -> Set<EntityListStatusFilter> = { _ in [] },
        isPinned: (Item) -> Bool = { _ in false },
        isDeprioritized: (Item) -> Bool = { _ in false }
    ) -> [Item] {
        let hiddenTagIDs = Set(preferences.hiddenTagIDs.filter { validTagIDs.contains($0) })
        let hiddenStatusFilters = Set(preferences.hiddenStatusFilters)

        let filteredItems = items.filter { item in
            matchesTagVisibility(
                hiddenTagIDs: hiddenTagIDs,
                itemTags: tags(item)
            )
                && matchesStatusVisibility(
                    hiddenStatusFilters: hiddenStatusFilters,
                    itemStatuses: statuses(item)
                )
        }

        return filteredItems.sorted { lhs, rhs in
            let lhsIsDeprioritized = isDeprioritized(lhs)
            let rhsIsDeprioritized = isDeprioritized(rhs)
            if lhsIsDeprioritized != rhsIsDeprioritized {
                return !lhsIsDeprioritized
            }

            let lhsIsPinned = isPinned(lhs)
            let rhsIsPinned = isPinned(rhs)
            if lhsIsPinned != rhsIsPinned {
                return lhsIsPinned
            }

            return compare(
                lhs,
                rhs,
                sort: preferences.effectiveSort(hasPremiumAccess: hasPremiumAccess),
                id: id,
                createdAt: createdAt,
                price: price
            )
        }
    }

    private static func matchesTagVisibility(
        hiddenTagIDs: Set<RecordID>,
        itemTags: [Tag]
    ) -> Bool {
        guard !hiddenTagIDs.isEmpty else { return true }

        let itemTagIDs = Set(itemTags.map(\.id))
        return itemTagIDs.isDisjoint(with: hiddenTagIDs)
    }

    private static func matchesStatusVisibility(
        hiddenStatusFilters: Set<EntityListStatusFilter>,
        itemStatuses: Set<EntityListStatusFilter>
    ) -> Bool {
        guard !hiddenStatusFilters.isEmpty else { return true }

        return itemStatuses.isDisjoint(with: hiddenStatusFilters)
    }

    private static func compare<Item>(
        _ lhs: Item,
        _ rhs: Item,
        sort: EntityListSortOption,
        id: (Item) -> RecordID,
        createdAt: (Item) -> Date,
        price: (Item) -> Int?
    ) -> Bool {
        switch sort {
        case .oldestToNewest:
            return compareDates(createdAt(lhs), createdAt(rhs), lhsID: id(lhs), rhsID: id(rhs), newerFirst: false)
        case .newestToOldest:
            return compareDates(createdAt(lhs), createdAt(rhs), lhsID: id(lhs), rhsID: id(rhs), newerFirst: true)
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
