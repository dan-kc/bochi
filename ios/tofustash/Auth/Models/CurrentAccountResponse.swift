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
            subscriptionExpiresAt: BackendTimestampParser.parse(subscriptionExpiresAt)
        )
    }
}

private enum BackendTimestampParser {
    private static let formatters: [DateFormatter] = {
        let base = DateFormatter()
        base.calendar = Calendar(identifier: .iso8601)
        base.locale = Locale(identifier: "en_US_POSIX")
        base.timeZone = TimeZone(secondsFromGMT: 0)

        let noFractional = base.copy() as! DateFormatter
        noFractional.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        let fractional = base.copy() as! DateFormatter
        fractional.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"

        return [fractional, noFractional]
    }()

    static func parse(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else { return nil }

        for formatter in formatters {
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }

        return nil
    }
}
