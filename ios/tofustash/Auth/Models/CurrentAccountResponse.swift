import Foundation

struct CurrentAccountResponse: Decodable, Equatable, Sendable {
    let email: String?
    let subscriptionSource: SubscriptionSource?
    let subscriptionStatus: SubscriptionStatus
    let isEntitled: Bool
    let subscriptionExpiresAt: String?

    func makeUser(id: String) -> AuthUser {
        AuthUser(
            id: id,
            email: email,
            subscriptionSource: subscriptionSource,
            subscriptionStatus: subscriptionStatus,
            isEntitled: isEntitled,
            subscriptionExpiresAt: AppDateCoding.parseBackendTimestamp(subscriptionExpiresAt)
        )
    }
}
