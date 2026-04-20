import Foundation

enum EntityListSortOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case oldestToNewest
    case newestToOldest
    case difficultyLowToHigh
    case difficultyHighToLow
    case priceLowToHigh
    case priceHighToLow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oldestToNewest: "Date created ascending"
        case .newestToOldest: "Date created descending"
        case .difficultyLowToHigh: "Difficulty ascending"
        case .difficultyHighToLow: "Difficulty descending"
        case .priceLowToHigh: "Price ascending"
        case .priceHighToLow: "Price descending"
        }
    }

    var fieldLabel: String {
        switch self {
        case .oldestToNewest:
            "Date Created"
        case .newestToOldest:
            "Date Created"
        case .difficultyLowToHigh:
            "Difficulty"
        case .difficultyHighToLow:
            "Difficulty"
        case .priceLowToHigh:
            "Price"
        case .priceHighToLow:
            "Price"
        }
    }

    var menuFieldLabel: String {
        switch self {
        case .oldestToNewest, .newestToOldest:
            "Created"
        case .difficultyLowToHigh, .difficultyHighToLow:
            "Difficulty"
        case .priceLowToHigh, .priceHighToLow:
            "Price"
        }
    }

    var directionLabel: String {
        switch self {
        case .oldestToNewest, .difficultyLowToHigh, .priceLowToHigh:
            "Ascending"
        case .newestToOldest, .difficultyHighToLow, .priceHighToLow:
            "Descending"
        }
    }

    var directionArrow: String {
        switch self {
        case .oldestToNewest, .difficultyLowToHigh, .priceLowToHigh:
            "↑"
        case .newestToOldest, .difficultyHighToLow, .priceHighToLow:
            "↓"
        }
    }
}

struct EntityListPreferences: Codable, Equatable, Sendable {
    var sort: EntityListSortOption = .priceHighToLow
    var selectedTagIDs: [RecordID] = []

    var hasActiveFilters: Bool {
        !selectedTagIDs.isEmpty
    }
}
