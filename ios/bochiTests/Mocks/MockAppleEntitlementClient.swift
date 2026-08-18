import Foundation
@testable import bochi

final class MockAppleEntitlementClient: AppleEntitlementClient, @unchecked Sendable {
    var currentEntitlementResult: AppleEntitlementStatus = .inactive
    var currentEntitlementCallCount = 0

    var restoreResult: Result<AppleEntitlementStatus, Error> = .success(.inactive)
    var restoreCallCount = 0

    var purchaseResult: Result<AppleEntitlementStatus, Error> = .success(.inactive)
    var purchaseCallCount = 0
    var lastPurchasedProductID: String?
    var lastPurchaseAppAccountToken: UUID?

    func currentEntitlement() async -> AppleEntitlementStatus {
        currentEntitlementCallCount += 1
        return currentEntitlementResult
    }

    func purchase(productID: String, appAccountToken: UUID?) async throws -> AppleEntitlementStatus {
        purchaseCallCount += 1
        lastPurchasedProductID = productID
        lastPurchaseAppAccountToken = appAccountToken
        return try purchaseResult.get()
    }

    func restorePurchases() async throws -> AppleEntitlementStatus {
        restoreCallCount += 1
        return try restoreResult.get()
    }
}
