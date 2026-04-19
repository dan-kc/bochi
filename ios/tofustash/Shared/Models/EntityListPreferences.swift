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

enum EntityListOptionalFieldFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case any
    case hasValue
    case missingValue

    var id: String { rawValue }

    func label(fieldName: String) -> String {
        switch self {
        case .any: "Any \(fieldName.lowercased()) state"
        case .hasValue: "Has \(fieldName.lowercased()) set"
        case .missingValue: "Does not have \(fieldName.lowercased()) set"
        }
    }
}

enum EntityListTagMatchMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case any
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: "Match Any Tag"
        case .all: "Match All Tags"
        }
    }
}

struct EntityListPreferences: Codable, Equatable, Sendable {
    var sort: EntityListSortOption = .priceHighToLow
    var difficultyFilter: EntityListOptionalFieldFilter = .any
    var frequencyFilter: EntityListOptionalFieldFilter = .any
    var selectedTagIDs: [RecordID] = []
    var tagMatchMode: EntityListTagMatchMode = .any

    var hasActiveFilters: Bool {
        difficultyFilter != .any || frequencyFilter != .any || !selectedTagIDs.isEmpty
    }
}
