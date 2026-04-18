import Foundation
import Testing
@testable import tofustash

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
            productID: "premium.monthly",
            originalTransactionID: "1000001234567889",
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

    // MARK: - Login / Register

    // Behaviour: when a user logs into an Apple-backed premium account, the
    // app uses `/auth/me` to render premium as account-owned rather than local-only.
    @Test func loginLoadsAccountAndApplePremiumState() async throws {
        let (manager, api, storage, entitlementClient) = makeSUT()
        entitlementClient.currentEntitlementResult = .inactive
        await manager.bootstrap()

        let tokens = TestHelpers.makeTokens(userId: "apple-user")
        api.loginResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(
                email: "apple@example.com",
                subscriptionSource: .apple,
                subscriptionStatus: .active,
                isEntitled: true
            )
        )

        try await manager.login(email: "apple@example.com", password: "password123")

        #expect(api.loginCallCount == 1)
        #expect(api.currentAccountCallCount == 1)
        #expect(storage.storedTokens == tokens)
        #expect(manager.sessionState == .signedInPremiumApple)
        #expect(manager.user?.email == "apple@example.com")
    }

    // Behaviour: when a new user registers and the backend reports no linked
    // subscription yet, the app should land in the normal signed-in free state.
    @Test func registerLoadsSignedInFreeState() async throws {
        let (manager, api, storage, entitlementClient) = makeSUT()
        entitlementClient.currentEntitlementResult = .inactive
        await manager.bootstrap()

        let tokens = TestHelpers.makeTokens(userId: "new-user")
        api.registerResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "new@example.com")
        )

        try await manager.register(email: "new@example.com", password: "password123")

        #expect(api.registerCallCount == 1)
        #expect(storage.storedTokens == tokens)
        #expect(manager.sessionState == .signedInFree)
        #expect(manager.user?.email == "new@example.com")
    }

    // Behaviour: when a user signs up after restoring on-device, the app should
    // explicitly link that Apple purchase to the new account instead of keeping
    // premium stranded as device-only state.
    @Test func registerAfterLocalRestoreLinksAccountToApplePremium() async throws {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let entitlementClient = MockAppleEntitlementClient()
        entitlementClient.currentEntitlementResult = AppleEntitlementStatus(
            isActive: true,
            productID: "premium.monthly",
            originalTransactionID: "1000001234567890",
            expirationDate: nil
        )

        let (manager, _, _, _) = makeSUT(
            apiClient: api,
            storage: storage,
            entitlementClient: entitlementClient
        )
        await manager.bootstrap()

        api.registerResult = .success(TestHelpers.makeTokens(userId: "linked-user"))
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

        try await manager.register(email: "linked@example.com", password: "password123")

        #expect(api.linkAppleSubscriptionCallCount == 1)
        #expect(api.lastLinkedOriginalTransactionID == "1000001234567890")
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
                productID: "premium.yearly",
                originalTransactionID: "1000001234567891",
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
                productID: "premium.yearly",
                originalTransactionID: "1000001234567892",
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
        #expect(manager.sessionState == .signedInPremiumApple)
        #expect(manager.hasUnlinkedAppleEntitlement == false)
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
            productID: "premium.monthly",
            originalTransactionID: "1000001234567893",
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

    // MARK: - Account Settings Actions

    // Behaviour: changing password uses the current signed-in backend session.
    @Test func changePasswordCallsAPIWithAccessToken() async throws {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let tokens = TestHelpers.makeTokens(userId: "user-1")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "user@example.com")
        )

        let (manager, _, _, _) = makeSUT(apiClient: api, storage: storage)
        await manager.bootstrap()
        try await manager.changePassword(currentPassword: "old", newPassword: "newpass123")

        #expect(api.changePasswordCallCount == 1)
        #expect(api.lastChangePasswordAccessToken != nil)
    }

    // Behaviour: changing email uses the current signed-in backend session.
    @Test func changeEmailCallsAPIWithAccessToken() async throws {
        let api = MockAuthAPIClient()
        let storage = MockTokenStorage()
        let tokens = TestHelpers.makeTokens(userId: "user-1")
        storage.storedTokens = tokens
        api.refreshTokensResult = .success(tokens)
        api.currentAccountResult = .success(
            TestHelpers.makeCurrentAccount(email: "user@example.com")
        )

        let (manager, _, _, _) = makeSUT(apiClient: api, storage: storage)
        await manager.bootstrap()
        try await manager.changeEmail(newEmail: "new@example.com", password: "password123")

        #expect(api.changeEmailCallCount == 1)
        #expect(api.lastChangeEmailAccessToken != nil)
    }
}
