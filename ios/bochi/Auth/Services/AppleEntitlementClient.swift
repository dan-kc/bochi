import Foundation
import StoreKit

struct AppleEntitlementStatus: Equatable, Sendable {
    let isActive: Bool
    let productID: String?
    let transactionID: String?
    let originalTransactionID: String?
    let environment: String?
    let expirationDate: Date?

    static let inactive = AppleEntitlementStatus(
        isActive: false,
        productID: nil,
        transactionID: nil,
        originalTransactionID: nil,
        environment: nil,
        expirationDate: nil
    )
}

protocol AppleEntitlementClient: Sendable {
    func currentEntitlement() async -> AppleEntitlementStatus
    func purchase(productID: String, appAccountToken: UUID?) async throws -> AppleEntitlementStatus
    func restorePurchases() async throws -> AppleEntitlementStatus
}

struct StaticAppleEntitlementClient: AppleEntitlementClient {
    let entitlement: AppleEntitlementStatus

    func currentEntitlement() async -> AppleEntitlementStatus {
        entitlement
    }

    func purchase(productID: String, appAccountToken: UUID?) async throws -> AppleEntitlementStatus {
        entitlement
    }

    func restorePurchases() async throws -> AppleEntitlementStatus {
        entitlement
    }
}

enum ApplePurchaseError: LocalizedError {
    case productUnavailable
    case pending
    case cancelled
    case unverified

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "This premium option is not available from the App Store yet."
        case .pending:
            return "The purchase is pending approval in the App Store."
        case .cancelled:
            return "The purchase was cancelled."
        case .unverified:
            return "The App Store could not verify this purchase."
        }
    }
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
                transactionID: String(transaction.id),
                originalTransactionID: String(transaction.originalID),
                environment: environmentName(for: transaction.environment),
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

    // Behaviour: buying premium should use StoreKit's verified transaction
    // result, then recompute entitlement from Apple's current-entitlements feed.
    func purchase(productID: String, appAccountToken: UUID?) async throws -> AppleEntitlementStatus {
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw ApplePurchaseError.productUnavailable
        }

        let purchaseOptions: Set<Product.PurchaseOption> = appAccountToken
            .map { [.appAccountToken($0)] }
            ?? []
        let result = try await product.purchase(options: purchaseOptions)

        switch result {
        case .success(.verified(let transaction)):
            await transaction.finish()
            return await currentEntitlement()
        case .success(.unverified):
            throw ApplePurchaseError.unverified
        case .pending:
            throw ApplePurchaseError.pending
        case .userCancelled:
            throw ApplePurchaseError.cancelled
        @unknown default:
            throw ApplePurchaseError.productUnavailable
        }
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
        }
    }

    private func environmentName(for environment: Any) -> String {
        let normalized = String(describing: environment).lowercased()

        if normalized.contains("xcode") {
            return "xcode"
        }
        if normalized.contains("sandbox") {
            return "sandbox"
        }

        return "production"
    }
}
