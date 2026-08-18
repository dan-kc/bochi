import Foundation

struct CurrentAccountResponse: Decodable, Equatable, Sendable {
    let email: String?
    let subscriptionSource: SubscriptionSource?
    let subscriptionStatus: SubscriptionStatus
    let subscriptionProductId: String?
    let isEntitled: Bool
    let subscriptionExpiresAt: String?

    func makeUser(id: String) -> AuthUser {
        AuthUser(
            id: id,
            email: email,
            subscriptionSource: subscriptionSource,
            subscriptionStatus: subscriptionStatus,
            subscriptionProductID: subscriptionProductId,
            isEntitled: isEntitled,
            subscriptionExpiresAt: AppDateCoding.parseBackendTimestamp(subscriptionExpiresAt)
        )
    }
}
