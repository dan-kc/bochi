import Foundation

enum SpecialOfferEntityKind: String, Codable, Sendable {
    case task
    case habit
    case reward
}

struct SpecialOffer: Identifiable, Equatable, Sendable, Codable, OwnerScopedRecord {
    let id: RecordID
    let entityKind: SpecialOfferEntityKind
    let entityID: RecordID
    let modifierPercent: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let expiresAt: Date

    func isActive(at now: Date = Date()) -> Bool {
        deletedAt == nil && expiresAt > now
    }
}
