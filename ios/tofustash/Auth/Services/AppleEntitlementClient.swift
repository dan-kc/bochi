import Foundation
import StoreKit

struct AppleEntitlementStatus: Equatable, Sendable {
    let isActive: Bool
    let productID: String?
    let originalTransactionID: String?
    let expirationDate: Date?

    static let inactive = AppleEntitlementStatus(
        isActive: false,
        productID: nil,
        originalTransactionID: nil,
        expirationDate: nil
    )
}

protocol AppleEntitlementClient: Sendable {
    func currentEntitlement() async -> AppleEntitlementStatus
    func restorePurchases() async throws -> AppleEntitlementStatus
}

struct StoreKitAppleEntitlementClient: AppleEntitlementClient {
    // Behaviour: app launch should reflect any already-active App Store
    // subscription without forcing the user to tap Restore every time.
    func currentEntitlement() async -> AppleEntitlementStatus {
        var bestMatch = AppleEntitlementStatus.inactive

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }

            if let expirationDate = transaction.expirationDate, expirationDate < Date() {
                continue
            }

            let candidate = AppleEntitlementStatus(
                isActive: true,
                productID: transaction.productID,
                originalTransactionID: String(transaction.originalID),
                expirationDate: transaction.expirationDate
            )

            if shouldPrefer(candidate, over: bestMatch) {
                bestMatch = candidate
            }
        }

        return bestMatch
    }

    // Behaviour: the restore button should resync purchases from the App Store,
    // then immediately reflect the latest local premium entitlement on-device.
    func restorePurchases() async throws -> AppleEntitlementStatus {
        try await AppStore.sync()
        return await currentEntitlement()
    }

    private func shouldPrefer(
        _ candidate: AppleEntitlementStatus,
        over current: AppleEntitlementStatus
    ) -> Bool {
        guard candidate.isActive else { return false }
        guard current.isActive else { return true }

        switch (candidate.expirationDate, current.expirationDate) {
        case (.none, _):
            return true
        case let (.some(candidateDate), .some(currentDate)):
            return candidateDate > currentDate
        case (.some, .none):
            return false
        case (.none, .none):
            return false
        }
    }
}
