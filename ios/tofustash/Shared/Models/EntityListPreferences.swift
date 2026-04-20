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
        case .oldestToNewest: "Date created (oldest to newest)"
        case .newestToOldest: "Date created (newest to oldest)"
        case .difficultyLowToHigh: "Difficulty (lowest to highest)"
        case .difficultyHighToLow: "Difficulty (highest to lowest)"
        case .priceLowToHigh: "Price (lowest to highest)"
        case .priceHighToLow: "Price (highest to lowest)"
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
