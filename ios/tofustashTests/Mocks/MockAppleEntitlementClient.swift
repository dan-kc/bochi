import Foundation
@testable import tofustash

final class MockAppleEntitlementClient: AppleEntitlementClient, @unchecked Sendable {
    var currentEntitlementResult: AppleEntitlementStatus = .inactive
    var currentEntitlementCallCount = 0

    var restoreResult: Result<AppleEntitlementStatus, Error> = .success(.inactive)
    var restoreCallCount = 0

    func currentEntitlement() async -> AppleEntitlementStatus {
        currentEntitlementCallCount += 1
        return currentEntitlementResult
    }

    func restorePurchases() async throws -> AppleEntitlementStatus {
        restoreCallCount += 1
        return try restoreResult.get()
    }
}
