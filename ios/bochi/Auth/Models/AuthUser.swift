import Foundation

enum SubscriptionSource: String, Codable, Equatable, Sendable {
    case apple
    case web
}

enum SubscriptionStatus: String, Codable, Equatable, Sendable {
    case none
    case active
    case gracePeriod = "grace_period"
    case billingRetry = "billing_retry"
    case expired
    case revoked

    // Behaviour: billing issues and expired/revoked subscriptions should lock
    // premium features without deleting the account itself.
    var isLapsed: Bool {
        switch self {
        case .billingRetry, .expired, .revoked:
            return true
        case .none, .active, .gracePeriod:
            return false
        }
    }
}

struct AuthUser: Equatable, Sendable {
    let id: String
    let email: String?
    let subscriptionSource: SubscriptionSource?
    let subscriptionStatus: SubscriptionStatus
    let subscriptionProductID: String?
    let isEntitled: Bool
    let subscriptionExpiresAt: Date?

    // Behaviour: account screens should show a real identity when possible, but
    // still have a stable fallback while the app is waiting for `/auth/me`.
    var displayName: String {
        if let email, !email.isEmpty {
            return email
        }

        return String(id.prefix(8)) + "..."
    }
}

enum AuthSessionState: String, Equatable, Sendable {
    case signedOutFree
    case signedOutPremiumRestored
    case signedInFree
    case signedInPremiumApple
    case signedInPremiumWeb
    case signedInLapsed

    var isPremiumEntitled: Bool {
        switch self {
        case .signedOutPremiumRestored, .signedInPremiumApple, .signedInPremiumWeb:
            return true
        case .signedOutFree, .signedInFree, .signedInLapsed:
            return false
        }
    }
}
