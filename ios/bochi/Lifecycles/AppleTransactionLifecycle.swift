import StoreKit
import SwiftUI

// Premium flow: StoreKit can publish renewals, refunds, and pending purchases
// after the original button tap, so the root view owns the long-running listener.
@MainActor
protocol AppleEntitlementRefreshing: AnyObject {
    func refreshAppleEntitlementFromStoreKit() async
}

extension AuthManager: AppleEntitlementRefreshing { }

@MainActor
enum AppleTransactionLifecycleCoordinator {
    static func refreshAfterTransactionUpdate(
        authManager: AppleEntitlementRefreshing
    ) async {
        await authManager.refreshAppleEntitlementFromStoreKit()
    }
}

private struct AppleTransactionLifecycleModifier: ViewModifier {
    let authManager: AuthManager

    func body(content: Content) -> some View {
        content.task {
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }

                if case .verified(let transaction) = result {
                    await transaction.finish()
                }

                await AppleTransactionLifecycleCoordinator.refreshAfterTransactionUpdate(
                    authManager: authManager
                )
            }
        }
    }
}

extension View {
    func appleTransactionLifecycle(authManager: AuthManager) -> some View {
        modifier(AppleTransactionLifecycleModifier(authManager: authManager))
    }
}
