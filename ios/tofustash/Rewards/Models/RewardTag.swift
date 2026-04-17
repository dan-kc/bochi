import Foundation

// Junction model for the many-to-many Reward ↔ Tag relationship.
// Keeping reward links separate from habit links means the global tag catalog
// stays shared while each feature owns its own association history.
struct RewardTag: Identifiable, Equatable, Sendable {
    let id: String
    let rewardId: String
    let tagId: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}
