import Foundation

nonisolated enum EntityListSortOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case oldestToNewest
    case newestToOldest
    case priceLowToHigh
    case priceHighToLow

    var id: String { rawValue }

    var isPremiumOnly: Bool {
        self != .priceHighToLow
    }

    var label: String {
        label(usesDamageTerminology: false)
    }

    func label(usesDamageTerminology: Bool) -> String {
        switch self {
        case .oldestToNewest: "Date created ascending"
        case .newestToOldest: "Date created descending"
        case .priceLowToHigh: "Price ascending"
        case .priceHighToLow: "Price descending"
        }
    }

    var fieldLabel: String {
        fieldLabel(usesDamageTerminology: false)
    }

    func fieldLabel(usesDamageTerminology: Bool) -> String {
        switch self {
        case .oldestToNewest:
            "Date Created"
        case .newestToOldest:
            "Date Created"
        case .priceLowToHigh:
            "Price"
        case .priceHighToLow:
            "Price"
        }
    }

    var menuFieldLabel: String {
        menuFieldLabel(usesDamageTerminology: false)
    }

    func menuFieldLabel(usesDamageTerminology: Bool) -> String {
        switch self {
        case .oldestToNewest, .newestToOldest:
            "Created"
        case .priceLowToHigh, .priceHighToLow:
            "Price"
        }
    }

    var directionLabel: String {
        switch self {
        case .oldestToNewest, .priceLowToHigh:
            "Ascending"
        case .newestToOldest, .priceHighToLow:
            "Descending"
        }
    }

    var directionArrow: String {
        switch self {
        case .oldestToNewest, .priceLowToHigh:
            "↑"
        case .newestToOldest, .priceHighToLow:
            "↓"
        }
    }
}

nonisolated enum EntityListStatusFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case taskGroup
    case task
    case recurringTask
    case reward
    case incomplete
    case completed
    case hidden
    case locked

    var id: String { rawValue }

    var label: String {
        switch self {
        case .taskGroup:
            "Task"
        case .task:
            "One-time"
        case .recurringTask:
            "Recurring"
        case .reward:
            "Reward"
        case .incomplete:
            "Incomplete"
        case .completed:
            "Completed"
        case .hidden:
            "Hidden"
        case .locked:
            "Locked"
        }
    }

    var icon: String {
        switch self {
        case .taskGroup:
            "checklist"
        case .task:
            "checkmark.square"
        case .recurringTask:
            "repeat"
        case .reward:
            "gift"
        case .incomplete:
            "circle"
        case .completed:
            "checkmark.circle"
        case .hidden:
            "eye.slash"
        case .locked:
            "lock"
        }
    }
}

struct EntityListPreferences: Codable, Equatable, Sendable {
    var sort: EntityListSortOption = .priceHighToLow
    var hiddenStatusFilters: [EntityListStatusFilter] = []
    var hiddenTagIDs: [RecordID] = []

    nonisolated func effectiveSort(hasPremiumAccess: Bool) -> EntityListSortOption {
        guard hasPremiumAccess || !sort.isPremiumOnly else {
            return .priceHighToLow
        }

        return sort
    }

    nonisolated func showsStatus(_ status: EntityListStatusFilter) -> Bool {
        !hiddenStatusFilters.contains(status)
    }

    nonisolated func showsTag(_ tagID: RecordID) -> Bool {
        !hiddenTagIDs.contains(tagID)
    }

    nonisolated var hasActiveFilters: Bool {
        !hiddenStatusFilters.isEmpty || !hiddenTagIDs.isEmpty
    }
}
