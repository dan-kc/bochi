import Foundation
import Testing
@testable import bochi

@MainActor
struct AuthManagerTests {

    private func makeSUT(
        apiClient: MockAuthAPIClient = MockAuthAPIClient(),
        storage: MockTokenStorage = MockTokenStorage(),
        entitlementClient: MockAppleEntitlementClient = MockAppleEntitlementClient()
    ) -> (AuthManager, MockAuthAPIClient, MockTokenStorage, MockAppleEntitlementClient) {
        let manager = AuthManager(
            apiClient: apiClient,
            tokenStorage: storage,
            appleEntitlementClient: entitlementClient
        )
        return (manager, apiClient, storage, entitlementClient)
    }

    // MARK: - Bootstrap

    // Behaviour: when the app launches with no saved backend session and no
    // local Apple entitlement, the user stays signed out in free local mode.
    @Test func bootstrapWithNoStoredTokensEntersSignedOutFree() async {
        let (manager, api, _, entitlementClient) = makeSUT()
        entitlementClient.currentEntitlementResult = .inactive

        await manager.bootstrap()

        #expect(api.refreshTokensCallCount == 0)
        #expect(manager.user == nil)
        #expect(manager.sessionState == .signedOutFree)
        #expect(manager.canSync == false)
        #expect(manager.isLoading == false)
    }

    // Behaviour: when the app launches signed out but the device already owns
    // an Apple subscription, premium unlocks locally without creating an account.
    @Test func bootstrapWithLocalAppleEntitlementEntersSignedOutPremiumRestored() async {
        let entitlement = AppleEntitlementStatus(
            isActive: true,
            productID: "lifetime.membership",
            transactionID: "2000001234567889",
            originalTransactionID: "1000001234567889",
            environment: "xcode",
            expirationDate: nil
        )
        let entitlementClient = MockAppleEntitlementClient()
        entitlementClient.currentEntitlementResult = entitlement

        let (manager, _, _, _) = makeSUT(entitlementClient: entitlementClient)
        await manager.bootstrap()

        #expect(manager.user == nil)
        #expect(manager.sessionState == .signedOutPremiumRestored)
        #expect(manager.isPremiumEntitled == true)
        #expect(manager.needsAccountToLinkPurchase == true)
    }

    // Behaviour: when a saved session exists, launch refreshes tokens and asks
    // `/auth/me` which account and subscription state should be shown.
    @Test func bootstrapWithStoredTokensRestoresSignedInAccountState() async {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let tokens = TestHelpers.makeTokens(userId: "user-456")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "user@example.com")
        )

        let (manager, _, _, _) = makeSUT(apiClient: api, storage: storage)
        await manager.bootstrap()

        #expect(api.refreshTokensCallCount == 1)
        #expect(api.currentAccountCallCount == 1)
        #expect(manager.user?.id == "user-456")
        #expect(manager.user?.email == "user@example.com")
        #expect(manager.sessionState == .signedInFree)
        #expect(manager.canSync == true)
    }

    // Behaviour: when refresh says the saved backend session is invalid, the
    // app clears it and returns to signed-out local mode.
    @Test func bootstrapWithExpiredSessionFallsBackToSignedOutFree() async {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        storage.storedTokens = TestHelpers.makeTokens(userId: "user-1")
        api.refreshTokensResult = .failure(
            ApiError(errors: nil, message: "Unauthorized", statusCode: 401)
        )

        let (manager, _, _, _) = makeSUT(apiClient: api, storage: storage)
        await manager.bootstrap()

        #expect(storage.clearCallCount == 1)
        #expect(manager.user == nil)
        #expect(manager.sessionState == .signedOutFree)
    }

    // MARK: - Sign in with Apple

    // Behaviour: when a user signs into an Apple-backed premium account, the
    // app uses `/auth/me` to render premium as account-owned rather than local-only.
    @Test func signInWithAppleLoadsAccountAndApplePremiumState() async throws {
        let (manager, api, storage, entitlementClient) = makeSUT()
        entitlementClient.currentEntitlementResult = .inactive
        await manager.bootstrap()

        let tokens = TestHelpers.makeTokens(userId: "apple-user")
        api.signInWithAppleResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(
                email: "apple@example.com",
                subscriptionSource: .apple,
                subscriptionStatus: .active,
                isEntitled: true
            )
        )

        try await manager.signInWithApple(
            identityToken: "identity-token",
            email: "apple@example.com",
            nonce: "nonce"
        )

        #expect(api.signInWithAppleCallCount == 1)
        #expect(api.lastAppleIdentityToken == "identity-token")
        #expect(api.lastAppleNonce == "nonce")
        #expect(api.currentAccountCallCount == 1)
        #expect(storage.storedTokens == tokens)
        #expect(manager.sessionState == .signedInPremiumApple)
        #expect(manager.user?.email == "apple@example.com")
    }

    // Behaviour: when a new Apple user signs in and the backend reports no linked
    // subscription yet, the app should land in the normal signed-in free state.
    @Test func signInWithAppleLoadsSignedInFreeState() async throws {
        let (manager, api, storage, entitlementClient) = makeSUT()
        entitlementClient.currentEntitlementResult = .inactive
        await manager.bootstrap()

        let tokens = TestHelpers.makeTokens(userId: "new-user")
        api.signInWithAppleResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "new@example.com")
        )

        try await manager.signInWithApple(
            identityToken: "new-identity-token",
            email: "new@example.com",
            nonce: "nonce"
        )

        #expect(api.signInWithAppleCallCount == 1)
        #expect(storage.storedTokens == tokens)
        #expect(manager.sessionState == .signedInFree)
        #expect(manager.user?.email == "new@example.com")
    }

    // Behaviour: a temporary Keychain write failure should not crash or undo a
    // successful sign-in; the access token remains usable in memory for sync.
    @Test func signInWithAppleContinuesWhenTokenStorageWriteIsTemporarilyUnavailable() async throws {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        storage.storeTokensError = TokenStorageError.temporarilyUnavailable(
            "Keychain write failed: User interaction is not allowed."
        )
        let entitlementClient = MockAppleEntitlementClient()
        entitlementClient.currentEntitlementResult = .inactive
        let (manager, _, _, _) = makeSUT(
            apiClient: api,
            storage: storage,
            entitlementClient: entitlementClient
        )
        await manager.bootstrap()

        let tokens = TestHelpers.makeTokens(userId: "storage-user")
        api.signInWithAppleResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "storage@example.com")
        )

        try await manager.signInWithApple(
            identityToken: "identity-token",
            email: "storage@example.com",
            nonce: "nonce"
        )

        #expect(storage.storeCallCount == 1)
        #expect(storage.storedTokens == nil)
        #expect(manager.user?.id == "storage-user")
        #expect(manager.user?.email == "storage@example.com")
        #expect(manager.sessionState == .signedInFree)
        #expect(manager.currentAccessTokenForSync() == tokens.accessToken)
    }

    // Behaviour: when a user signs in after restoring on-device, the app should
    // explicitly link that Apple purchase to the new account instead of keeping
    // premium stranded as device-only state.
    @Test func signInWithAppleAfterLocalRestoreLinksAccountToApplePremium() async throws {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let entitlementClient = MockAppleEntitlementClient()
        entitlementClient.currentEntitlementResult = AppleEntitlementStatus(
            isActive: true,
            productID: "lifetime.membership",
            transactionID: "2000001234567890",
            originalTransactionID: "1000001234567890",
            environment: "xcode",
            expirationDate: nil
        )

        let (manager, _, _, _) = makeSUT(
            apiClient: api,
            storage: storage,
            entitlementClient: entitlementClient
        )
        await manager.bootstrap()

        api.signInWithAppleResult = .success(TestHelpers.makeTokens(userId: "linked-user"))
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "linked@example.com")
        )
        api.linkAppleSubscriptionResult = .success(
            TestHelpers.makeCurrentAccount(
                email: "linked@example.com",
                subscriptionSource: .apple,
                subscriptionStatus: .active,
                isEntitled: true
            )
        )

        try await manager.signInWithApple(
            identityToken: "linked-identity-token",
            email: "linked@example.com",
            nonce: "nonce"
        )

        #expect(api.linkAppleSubscriptionCallCount == 1)
        #expect(api.lastLinkedTransactionID == "2000001234567890")
        #expect(api.lastLinkedOriginalTransactionID == "1000001234567890")
        #expect(api.lastLinkedProductID == "lifetime.membership")
        #expect(api.lastLinkedEnvironment == "xcode")
        #expect(manager.sessionState == .signedInPremiumApple)
        #expect(manager.hasUnlinkedAppleEntitlement == false)
        #expect(manager.user?.email == "linked@example.com")
    }

    // MARK: - Restore Purchases

    // Behaviour: restoring while signed out should unlock local premium on the
    // device without silently creating or signing into a backend account.
    @Test func restorePurchasesWhileSignedOutUnlocksLocalPremiumOnly() async throws {
        let entitlementClient = MockAppleEntitlementClient()
        entitlementClient.currentEntitlementResult = .inactive
        entitlementClient.restoreResult = .success(
            AppleEntitlementStatus(
                isActive: true,
                productID: "annual.membership",
                transactionID: "2000001234567891",
                originalTransactionID: "1000001234567891",
                environment: "xcode",
                expirationDate: nil
            )
        )

        let (manager, _, _, _) = makeSUT(entitlementClient: entitlementClient)
        await manager.bootstrap()
        try await manager.restorePurchases()

        #expect(entitlementClient.restoreCallCount == 1)
        #expect(manager.user == nil)
        #expect(manager.sessionState == .signedOutPremiumRestored)
        #expect(manager.needsAccountToLinkPurchase == true)
    }

    // Behaviour: when a signed-in user restores a valid Apple purchase, the
    // app should attach that purchase to the current account and immediately
    // move from free account state to Apple-backed premium account state.
    @Test func restorePurchasesWhileSignedInLinksApplePremiumToAccount() async throws {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let entitlementClient = MockAppleEntitlementClient()
        let tokens = TestHelpers.makeTokens(userId: "restore-user")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "restore@example.com")
        )
        entitlementClient.currentEntitlementResult = .inactive
        entitlementClient.restoreResult = .success(
            AppleEntitlementStatus(
                isActive: true,
                productID: "annual.membership",
                transactionID: "2000001234567892",
                originalTransactionID: "1000001234567892",
                environment: "xcode",
                expirationDate: nil
            )
        )
        api.linkAppleSubscriptionResult = .success(
            TestHelpers.makeCurrentAccount(
                email: "restore@example.com",
                subscriptionSource: .apple,
                subscriptionStatus: .active,
                isEntitled: true
            )
        )

        let (manager, _, _, _) = makeSUT(
            apiClient: api,
            storage: storage,
            entitlementClient: entitlementClient
        )
        await manager.bootstrap()
        try await manager.restorePurchases()

        #expect(api.linkAppleSubscriptionCallCount == 1)
        #expect(api.lastLinkedTransactionID == "2000001234567892")
        #expect(api.lastLinkedProductID == "annual.membership")
        #expect(api.lastLinkedEnvironment == "xcode")
        #expect(manager.sessionState == .signedInPremiumApple)
        #expect(manager.hasUnlinkedAppleEntitlement == false)
    }

    // Behaviour: if Apple restore succeeds while the backend is offline, the
    // local entitlement should stay available for a later account-link retry.
    @Test func restorePurchasesWhileSignedInWithLinkFailureKeepsLocalAppleEntitlement() async throws {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let entitlementClient = MockAppleEntitlementClient()
        let tokens = TestHelpers.makeTokens(userId: "restore-offline-user")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "restore-offline@example.com")
        )
        entitlementClient.currentEntitlementResult = .inactive
        entitlementClient.restoreResult = .success(
            AppleEntitlementStatus(
                isActive: true,
                productID: "monthly.membership",
                transactionID: "2000007234567892",
                originalTransactionID: "1000007234567892",
                environment: "xcode",
                expirationDate: Date(timeIntervalSince1970: 1_900_000_000)
            )
        )
        api.linkAppleSubscriptionResult = .failure(MockError.notConfigured)

        let (manager, _, _, _) = makeSUT(
            apiClient: api,
            storage: storage,
            entitlementClient: entitlementClient
        )
        await manager.bootstrap()
        let result = try await manager.restorePurchases()

        #expect(result == .activeOnDeviceAccountLinkFailed)
        #expect(result.shouldShowPremiumWelcome == false)
        #expect(api.linkAppleSubscriptionCallCount == 1)
        #expect(manager.localAppleEntitlement.isActive == true)
        #expect(manager.hasUnlinkedAppleEntitlement == true)
        #expect(manager.sessionState == .signedInFree)
    }

    // MARK: - Purchase Premium

    // Behaviour: buying premium while signed out should unlock this device
    // without creating a backend account behind the user's back.
    @Test func purchasePremiumWhileSignedOutUnlocksLocalPremiumOnly() async throws {
        let entitlementClient = MockAppleEntitlementClient()
        entitlementClient.currentEntitlementResult = .inactive
        entitlementClient.purchaseResult = .success(
            AppleEntitlementStatus(
                isActive: true,
                productID: "lifetime.membership",
                transactionID: "2000001234567896",
                originalTransactionID: "1000001234567896",
                environment: "xcode",
                expirationDate: nil
            )
        )

        let (manager, api, _, _) = makeSUT(entitlementClient: entitlementClient)
        await manager.bootstrap()
        let result = try await manager.purchasePremium(productID: "lifetime.membership")

        #expect(result == .activeOnDeviceNeedsAccount)
        #expect(result.shouldShowPremiumWelcome == true)
        #expect(entitlementClient.purchaseCallCount == 1)
        #expect(entitlementClient.lastPurchasedProductID == "lifetime.membership")
        #expect(api.linkAppleSubscriptionCallCount == 0)
        #expect(manager.sessionState == .signedOutPremiumRestored)
        #expect(manager.needsAccountToLinkPurchase == true)
    }

    // Behaviour: pending StoreKit purchases should wait for Transaction.updates
    // instead of unlocking premium before Apple completes the transaction.
    @Test func pendingPremiumPurchaseDoesNotUnlockImmediately() async {
        let entitlementClient = MockAppleEntitlementClient()
        entitlementClient.currentEntitlementResult = .inactive
        entitlementClient.purchaseResult = .failure(ApplePurchaseError.pending)

        let (manager, api, _, _) = makeSUT(entitlementClient: entitlementClient)
        await manager.bootstrap()

        do {
            _ = try await manager.purchasePremium(productID: "monthly.membership")
            Issue.record("Expected pending purchase to throw.")
        } catch ApplePurchaseError.pending {
            // Expected: StoreKit will publish completion later via Transaction.updates.
        } catch {
            Issue.record("Expected pending purchase error, got \(error).")
        }

        #expect(entitlementClient.purchaseCallCount == 1)
        #expect(api.linkAppleSubscriptionCallCount == 0)
        #expect(manager.localAppleEntitlement.isActive == false)
        #expect(manager.sessionState == .signedOutFree)
    }

    // Behaviour: buying premium while signed in should attach the Apple purchase
    // to the current account so premium and sync use the same backend identity.
    @Test func purchasePremiumWhileSignedInLinksApplePremiumToAccount() async throws {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let entitlementClient = MockAppleEntitlementClient()
        let tokens = TestHelpers.makeTokens(userId: "purchase-user")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "purchase@example.com")
        )
        entitlementClient.currentEntitlementResult = .inactive
        entitlementClient.purchaseResult = .success(
            AppleEntitlementStatus(
                isActive: true,
                productID: "lifetime.membership",
                transactionID: "2000001234567897",
                originalTransactionID: "1000001234567897",
                environment: "xcode",
                expirationDate: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        api.linkAppleSubscriptionResult = .success(
            TestHelpers.makeCurrentAccount(
                email: "purchase@example.com",
                subscriptionSource: .apple,
                subscriptionStatus: .active,
                subscriptionProductId: "lifetime.membership",
                isEntitled: true
            )
        )

        let (manager, _, _, _) = makeSUT(
            apiClient: api,
            storage: storage,
            entitlementClient: entitlementClient
        )
        await manager.bootstrap()
        let result = try await manager.purchasePremium(productID: "lifetime.membership")

        #expect(result == .activeForAccount)
        #expect(result.shouldShowPremiumWelcome == true)
        #expect(entitlementClient.purchaseCallCount == 1)
        #expect(api.linkAppleSubscriptionCallCount == 1)
        #expect(api.lastLinkedTransactionID == "2000001234567897")
        #expect(api.lastLinkedOriginalTransactionID == "1000001234567897")
        #expect(api.lastLinkedProductID == "lifetime.membership")
        #expect(api.lastLinkedEnvironment == "xcode")
        #expect(manager.sessionState == .signedInPremiumApple)
        #expect(manager.user?.subscriptionProductID == "lifetime.membership")
    }

    // Behaviour: if StoreKit completes but the backend link call fails, the app
    // should not pretend the App Store purchase failed or lose the retry state.
    @Test func purchasePremiumWhileSignedInWithLinkFailureKeepsLocalAppleEntitlement() async throws {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let entitlementClient = MockAppleEntitlementClient()
        let tokens = TestHelpers.makeTokens(userId: "purchase-offline-user")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "purchase-offline@example.com")
        )
        entitlementClient.currentEntitlementResult = .inactive
        entitlementClient.purchaseResult = .success(
            AppleEntitlementStatus(
                isActive: true,
                productID: "monthly.membership",
                transactionID: "2000008234567897",
                originalTransactionID: "1000008234567897",
                environment: "xcode",
                expirationDate: Date(timeIntervalSince1970: 1_900_000_000)
            )
        )
        api.linkAppleSubscriptionResult = .failure(MockError.notConfigured)

        let (manager, _, _, _) = makeSUT(
            apiClient: api,
            storage: storage,
            entitlementClient: entitlementClient
        )
        await manager.bootstrap()
        let result = try await manager.purchasePremium(productID: "monthly.membership")

        #expect(result == .activeOnDeviceAccountLinkFailed)
        #expect(result.shouldShowPremiumWelcome == false)
        #expect(entitlementClient.purchaseCallCount == 1)
        #expect(api.linkAppleSubscriptionCallCount == 1)
        #expect(manager.localAppleEntitlement.isActive == true)
        #expect(manager.hasUnlinkedAppleEntitlement == true)
        #expect(manager.sessionState == .signedInFree)
    }

    // Behaviour: signed-in purchases should include the backend account UUID so
    // Apple transaction history can be associated with the same account later.
    @Test func purchasePremiumWhileSignedInPassesAccountTokenToStoreKit() async throws {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let entitlementClient = MockAppleEntitlementClient()
        let userID = "00000000-0000-0000-0000-000000000123"
        let tokens = TestHelpers.makeTokens(userId: userID)
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "token@example.com")
        )
        entitlementClient.currentEntitlementResult = .inactive
        entitlementClient.purchaseResult = .success(
            AppleEntitlementStatus(
                isActive: true,
                productID: "monthly.membership",
                transactionID: "2000005234567897",
                originalTransactionID: "1000005234567897",
                environment: "xcode",
                expirationDate: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        api.linkAppleSubscriptionResult = .success(
            TestHelpers.makeCurrentAccount(
                email: "token@example.com",
                subscriptionSource: .apple,
                subscriptionStatus: .active,
                subscriptionProductId: "monthly.membership",
                isEntitled: true
            )
        )

        let (manager, _, _, _) = makeSUT(
            apiClient: api,
            storage: storage,
            entitlementClient: entitlementClient
        )
        await manager.bootstrap()
        try await manager.purchasePremium(productID: "monthly.membership")

        #expect(entitlementClient.lastPurchaseAppAccountToken == UUID(uuidString: userID))
        #expect(api.lastLinkedTransactionID == "2000005234567897")
        #expect(api.lastLinkedEnvironment == "xcode")
    }

    // Behaviour: StoreKit transaction updates outside a button tap should
    // refresh the local entitlement and link it to the signed-in account.
    @Test func refreshAppleEntitlementFromStoreKitLinksUpdatedEntitlement() async {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let entitlementClient = MockAppleEntitlementClient()
        let tokens = TestHelpers.makeTokens(userId: "refresh-user")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "refresh@example.com")
        )
        entitlementClient.currentEntitlementResult = .inactive

        let (manager, _, _, _) = makeSUT(
            apiClient: api,
            storage: storage,
            entitlementClient: entitlementClient
        )
        await manager.bootstrap()

        entitlementClient.currentEntitlementResult = AppleEntitlementStatus(
            isActive: true,
            productID: "annual.membership",
            transactionID: "2000006234567897",
            originalTransactionID: "1000006234567897",
            environment: "xcode",
            expirationDate: Date(timeIntervalSince1970: 1_900_000_000)
        )
        api.linkAppleSubscriptionResult = .success(
            TestHelpers.makeCurrentAccount(
                email: "refresh@example.com",
                subscriptionSource: .apple,
                subscriptionStatus: .active,
                subscriptionProductId: "annual.membership",
                isEntitled: true
            )
        )

        await manager.refreshAppleEntitlementFromStoreKit()

        #expect(api.linkAppleSubscriptionCallCount == 1)
        #expect(api.lastLinkedTransactionID == "2000006234567897")
        #expect(api.lastLinkedProductID == "annual.membership")
        #expect(manager.sessionState == .signedInPremiumApple)
    }

    // MARK: - Logout

    // Behaviour: logging out should clear the backend session but keep any
    // active Apple entitlement visible as device-level premium.
    @Test func logoutPreservesLocalPremiumRestoreState() async throws {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let entitlementClient = MockAppleEntitlementClient()
        let tokens = TestHelpers.makeTokens(userId: "user-1")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "user@example.com")
        )
        entitlementClient.currentEntitlementResult = AppleEntitlementStatus(
            isActive: true,
            productID: "lifetime.membership",
            transactionID: "2000001234567893",
            originalTransactionID: "1000001234567893",
            environment: "xcode",
            expirationDate: nil
        )

        let (manager, _, _, _) = makeSUT(
            apiClient: api,
            storage: storage,
            entitlementClient: entitlementClient
        )
        await manager.bootstrap()

        await manager.logout()

        #expect(storage.clearCallCount == 1)
        #expect(manager.user == nil)
        #expect(manager.sessionState == .signedOutPremiumRestored)
    }

    // Behaviour: deleting an account should remove the backend account, clear
    // local session tokens, and publish the deleted owner so app lifecycles can
    // remove account-scoped local data.
    @Test func deleteAccountClearsSessionAndPublishesDeletedOwner() async throws {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let entitlementClient = MockAppleEntitlementClient()
        let tokens = TestHelpers.makeTokens(userId: "deleted-user")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "deleted@example.com")
        )
        entitlementClient.currentEntitlementResult = .inactive

        let (manager, _, _, _) = makeSUT(
            apiClient: api,
            storage: storage,
            entitlementClient: entitlementClient
        )
        await manager.bootstrap()

        try await manager.deleteAccount()

        #expect(api.deleteAccountCallCount == 1)
        #expect(api.lastDeleteAccountAccessToken == tokens.accessToken)
        #expect(storage.clearCallCount == 1)
        #expect(manager.user == nil)
        #expect(manager.currentAccessTokenForSync() == nil)
        #expect(manager.sessionState == .signedOutFree)
        #expect(manager.accountDeletionEvent?.userID == "deleted-user")
    }

    // Behaviour: if the backend refuses account deletion, the app should keep
    // the existing signed-in session instead of pretending the account is gone.
    @Test func deleteAccountFailureLeavesSessionIntact() async {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let tokens = TestHelpers.makeTokens(userId: "delete-failed-user")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "delete-failed@example.com")
        )
        api.deleteAccountResult = .failure(ApiError.genericFailure(message: "Delete failed."))

        let (manager, _, _, _) = makeSUT(apiClient: api, storage: storage)
        await manager.bootstrap()

        do {
            try await manager.deleteAccount()
            Issue.record("Expected deleteAccount to throw.")
        } catch {
            // Expected: the UI should display the deletion error and leave the session alone.
        }

        #expect(api.deleteAccountCallCount == 1)
        #expect(storage.clearCallCount == 0)
        #expect(manager.user?.id == "delete-failed-user")
        #expect(manager.sessionState == .signedInFree)
        #expect(manager.accountDeletionEvent == nil)
    }

    // MARK: - Account States

    // Behaviour: a web subscription should unlock premium through account state
    // alone, even if the device has no local Apple restore on it.
    @Test func bootstrapLoadsWebPremiumAccountState() async {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let tokens = TestHelpers.makeTokens(userId: "web-user")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(
                email: "web@example.com",
                subscriptionSource: .web,
                subscriptionStatus: .active,
                isEntitled: true
            )
        )

        let (manager, _, _, _) = makeSUT(apiClient: api, storage: storage)
        await manager.bootstrap()

        #expect(manager.sessionState == .signedInPremiumWeb)
        #expect(manager.isPremiumEntitled == true)
    }

    // Behaviour: expired or billing-issue accounts should keep sync/account
    // ownership while clearly dropping premium entitlement.
    @Test func bootstrapLoadsLapsedAccountState() async {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let tokens = TestHelpers.makeTokens(userId: "lapsed-user")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(
                email: "lapsed@example.com",
                subscriptionSource: .apple,
                subscriptionStatus: .expired,
                isEntitled: false,
                subscriptionExpiresAt: "2026-04-18T09:00:00"
            )
        )

        let (manager, _, _, _) = makeSUT(apiClient: api, storage: storage)
        await manager.bootstrap()

        #expect(manager.sessionState == .signedInLapsed)
        #expect(manager.canSync == true)
        #expect(manager.isPremiumEntitled == false)
        #expect(manager.user?.subscriptionExpiresAt != nil)
    }

    // Behaviour: account bootstrap should accept backend subscription expiry
    // timestamps with fractional seconds so premium state survives unchanged.
    @Test func bootstrapLoadsLapsedAccountStateWithFractionalExpiry() async {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let tokens = TestHelpers.makeTokens(userId: "lapsed-user")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(
                email: "lapsed@example.com",
                subscriptionSource: .apple,
                subscriptionStatus: .expired,
                isEntitled: false,
                subscriptionExpiresAt: "2026-04-18T09:00:00.123456"
            )
        )

        let (manager, _, _, _) = makeSUT(apiClient: api, storage: storage)
        await manager.bootstrap()

        #expect(manager.sessionState == .signedInLapsed)
        #expect(manager.canSync == true)
        #expect(manager.isPremiumEntitled == false)
        #expect(manager.user?.subscriptionExpiresAt != nil)
    }

}

private final class MockAuthURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
struct LiveAuthAPIClientTests {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockAuthURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeClient() throws -> LiveAuthAPIClient {
        LiveAuthAPIClient(
            baseURL: try #require(URL(string: "https://example.com")),
            session: makeSession()
        )
    }

    private func tokensData(userID: String = "user-123") throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "accessToken": TestHelpers.makeJWT(subject: userID, expiresAt: 1_900_000_000),
                "refreshToken": "refresh-\(userID)"
            ]
        )
    }

    private func accountData(email: String = "user@example.com") throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "email": email,
                "subscriptionSource": NSNull(),
                "subscriptionStatus": "none",
                "subscriptionProductId": NSNull(),
                "isEntitled": false,
                "subscriptionExpiresAt": NSNull()
            ]
        )
    }

    private nonisolated static func bodyData(from request: URLRequest) throws -> Data {
        if let httpBody = request.httpBody {
            return httpBody
        }

        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    // Behaviour: Apple sign-in should send the Apple identity token to the
    // backend Apple auth endpoint and decode the returned token pair.
    @Test func signInWithAppleBuildsRequestAndDecodesTokens() async throws {
        let client = try makeClient()
        let responseData = try tokensData(userID: "apple-user")

        MockAuthURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/auth/sign-in-with-apple")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try Self.bodyData(from: request)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["email"] == "user@example.com")
            #expect(json["identityToken"] == "identity-token")
            #expect(json["nonce"] == "nonce")
            #expect(json["authorizationCode"] == "authorization-code")
            let url = try #require(request.url)
            return (
                try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)),
                responseData
            )
        }
        defer { MockAuthURLProtocol.requestHandler = nil }

        let tokens = try await client.signInWithApple(
            identityToken: "identity-token",
            email: "user@example.com",
            nonce: "nonce",
            authorizationCode: "authorization-code"
        )

        #expect(tokens.refreshToken == "refresh-apple-user")
    }

    // Behaviour: authenticated account calls should carry the bearer token and
    // use the backend account endpoint without a JSON body.
    @Test func getCurrentAccountUsesBearerAuthorization() async throws {
        let client = try makeClient()
        let responseData = try accountData()

        MockAuthURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/auth/me")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-123")
            #expect(request.httpBody == nil)
            let url = try #require(request.url)
            return (
                try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)),
                responseData
            )
        }
        defer { MockAuthURLProtocol.requestHandler = nil }

        let account = try await client.getCurrentAccount(accessToken: "access-123")

        #expect(account.email == "user@example.com")
    }

    // Behaviour: linking a restored Apple purchase should send the transaction
    // id and backend-formatted expiration date with account authorization.
    @Test func linkAppleSubscriptionBuildsAuthorizedRequestBody() async throws {
        let client = try makeClient()
        let responseData = try accountData(email: "apple@example.com")
        let expiration = Date(timeIntervalSince1970: 1_800_000_000)

        MockAuthURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/auth/link-apple-subscription")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-123")
            let body = try Self.bodyData(from: request)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json["transactionId"] == "200000123")
            #expect(json["originalTransactionId"] == "100000123")
            #expect(json["productId"] == "lifetime.membership")
            #expect(json["environment"] == "xcode")
            #expect(json["subscriptionExpiresAt"]?.hasSuffix("Z") == true)
            let url = try #require(request.url)
            return (
                try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)),
                responseData
            )
        }
        defer { MockAuthURLProtocol.requestHandler = nil }

        let account = try await client.linkAppleSubscription(
            transactionID: "200000123",
            originalTransactionID: "100000123",
            productID: "lifetime.membership",
            environment: "xcode",
            subscriptionExpiresAt: expiration,
            accessToken: "access-123"
        )

        #expect(account.email == "apple@example.com")
    }

    // Behaviour: account deletion should call the dedicated backend endpoint
    // with the current access token and no request body.
    @Test func deleteAccountUsesAuthorizedDeleteRequest() async throws {
        let client = try makeClient()
        let responseData = try JSONSerialization.data(withJSONObject: ["success": true])

        MockAuthURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/auth/account")
            #expect(request.httpMethod == "DELETE")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-123")
            #expect(request.httpBody == nil)
            let url = try #require(request.url)
            return (
                try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)),
                responseData
            )
        }
        defer { MockAuthURLProtocol.requestHandler = nil }

        try await client.deleteAccount(accessToken: "access-123")
    }

    // Behaviour: backend validation errors should surface as ApiError values
    // with the server status code and message intact.
    @Test func nonSuccessStatusThrowsApiErrorFromServerPayload() async throws {
        let client = try makeClient()
        let errorData = try JSONSerialization.data(
            withJSONObject: [
                "message": "Invalid credentials",
                "errors": [["code": "invalid_credentials", "message": "Invalid credentials"]]
            ]
        )

        MockAuthURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            return (
                try #require(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)),
                errorData
            )
        }
        defer { MockAuthURLProtocol.requestHandler = nil }

        do {
            _ = try await client.signInWithApple(
                identityToken: "bad-token",
                email: "user@example.com",
                nonce: "nonce"
            )
            Issue.record("Expected ApiError")
        } catch let error as ApiError {
            #expect(error.statusCode == 401)
            #expect(error.userFacingMessage == "Invalid credentials")
        }
    }

    // Behaviour: transport failures should become the app's network failure
    // error instead of leaking URLSession details to callers.
    @Test func networkFailureThrowsUserFacingApiError() async throws {
        let client = try makeClient()

        MockAuthURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { MockAuthURLProtocol.requestHandler = nil }

        do {
            _ = try await client.signInWithApple(
                identityToken: "identity-token",
                email: "user@example.com",
                nonce: "nonce"
            )
            Issue.record("Expected network ApiError")
        } catch let error as ApiError {
            #expect(error.userFacingMessage.contains("offline") || error.userFacingMessage.contains("network"))
        }
    }

    // Behaviour: non-HTTP responses and unreadable JSON should become generic
    // app errors that callers can display safely.
    @Test func invalidHTTPOrJSONResponsesThrowGenericApiErrors() async throws {
        let client = try makeClient()

        MockAuthURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            return (URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil), Data())
        }

        do {
            _ = try await client.signInWithApple(
                identityToken: "identity-token",
                email: "user@example.com",
                nonce: "nonce"
            )
            Issue.record("Expected invalid response ApiError")
        } catch let error as ApiError {
            #expect(error.userFacingMessage == "The server returned an invalid response.")
        }

        MockAuthURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            return (
                try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)),
                Data("{".utf8)
            )
        }
        defer { MockAuthURLProtocol.requestHandler = nil }

        do {
            _ = try await client.signInWithApple(
                identityToken: "identity-token",
                email: "user@example.com",
                nonce: "nonce"
            )
            Issue.record("Expected decode ApiError")
        } catch let error as ApiError {
            #expect(error.userFacingMessage == "The app could not read the server response.")
        }
    }
}
