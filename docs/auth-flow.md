# Auth Flow Code Guide

Use this to read the auth code. The main invariant is:

> Backend account identity, StoreKit device entitlement, and backend premium
> entitlement are separate facts.

`AuthManager` derives the SwiftUI state from those facts.

## Read First

- `ios/bochi/Auth/AuthManager.swift`: session state machine.
- `ios/bochi/Auth/Models/AuthUser.swift`: user/subscription/session models.
- `ios/bochi/Auth/Services/AuthAPIClient.swift`: backend auth calls.
- `ios/bochi/Auth/Services/AppleEntitlementClient.swift`: StoreKit boundary.
- `ios/bochi/SettingsView.swift`: account/premium UI behavior.
- `ios/bochi/Lifecycles/AccountDeletionLifecycle.swift`: local cleanup after account deletion.
- `backend/src/router.rs`: auth route wiring.
- `backend/src/routes.rs`: auth endpoint handlers.
- `backend/src/database.rs`: account/subscription persistence.
- `ios/bochiTests/AuthManagerTests.swift`: expected iOS behavior.
- `backend/tests/auth`: backend auth behavior.

## Session States

`AuthSessionState` is UI-facing only. The backend does not store this enum.

- `signedOutFree`: no account, no local Apple entitlement.
- `signedOutPremiumRestored`: no account, active StoreKit entitlement on this device.
- `signedInFree`: account exists, not premium-entitled.
- `signedInPremiumApple`: account entitlement is linked to Apple billing.
- `signedInPremiumWeb`: account entitlement is linked to web billing.
- `signedInLapsed`: account exists, sync remains available, premium is locked.

`AuthManager.canSync` is simply `user != nil`.

## Backend Endpoints

Implemented by `LiveAuthAPIClient` and `backend/src/routes.rs`:

- `POST /auth/sign-in-with-apple`
- `POST /auth/refresh-tokens`
- `POST /auth/logout`
- `DELETE /auth/account`
- `GET /auth/me`
- `POST /auth/link-apple-subscription`

`/auth/me` is the account truth used after sign-in and refresh. It returns:

- `email`
- `subscriptionSource`
- `subscriptionStatus`
- `subscriptionProductId`
- `isEntitled`
- `subscriptionExpiresAt`

The backend treats `active` and `grace_period` as entitled. `none`,
`billing_retry`, `expired`, and `revoked` are not entitled.

## Flow Notes

### App Launch

`AuthManager.bootstrap()`:

1. reads StoreKit local entitlement
2. reads stored backend tokens
3. builds a provisional user from the JWT if possible
4. refreshes tokens
5. calls `/auth/me`
6. links local Apple entitlement if possible
7. recomputes `AuthSessionState`

Network failure during bootstrap should not force logout if a provisional signed-in
state can still be shown. A `401` refresh clears tokens.

### Sign In With Apple

`signInWithApple(...)` calls `/auth/sign-in-with-apple`, stores returned tokens,
then follows the same `/auth/me` and Apple-link path as bootstrap.

The Apple identity token signs into the app account. It is separate from StoreKit
purchase restore.

When iOS provides an Apple authorization code, the app sends it with sign-in.
If backend Apple Sign in client-secret configuration is present, the backend
exchanges that code for an Apple refresh token so account deletion can ask Apple
to revoke the Sign in with Apple grant. Missing Apple token configuration should
not block app sign-in.

### Restore Or Purchase Premium

`restorePurchases()` and `purchasePremium(productID:)` update
`localAppleEntitlement` through StoreKit first.

If an account is signed in, the device entitlement is active, the account is not
already entitled, and StoreKit has an `originalTransactionID`,
`linkLocalAppleEntitlementIfPossible()` calls `/auth/link-apple-subscription`.

If no account is signed in, the app may enter `signedOutPremiumRestored`; it does
not create a backend account.

### Logout

Logout clears backend tokens and user state. It does not clear StoreKit
entitlement, so a device with an active Apple entitlement becomes
`signedOutPremiumRestored`.

### Account Deletion

`deleteAccount()` calls `DELETE /auth/account` with the current access token.
The backend deletes the Bochi user row, which cascades account-owned app data,
refresh tokens, sync state, and premium entitlement links. If an Apple Sign in
refresh token was captured, the backend attempts Apple token revocation before
deleting the account.

On iOS, account deletion is stronger than logout:

- clears stored backend tokens
- clears in-memory account state
- preserves any local StoreKit entitlement visible on the device
- publishes `AccountDeletionEvent`
- `accountDeletionLifecycle(...)` purges local rows for the deleted owner and
  cancels pending reminder notifications for that owner

Deleting a Bochi account does not cancel Apple billing. The Settings sheet links
to Apple's subscription management page when Apple billing may be active.

## Apple Linking Rules

`/auth/link-apple-subscription` attaches one StoreKit original transaction ID to
one backend account.

Important behavior:

- requires auth
- rejects a transaction already linked to a different user with `409`
- stores Apple source/status/product/expiry on success
- returns the same account shape as `/auth/me`

## Sync Boundary

Auth does not perform sync itself.

`bochiApp` wires `authSessionLifecycle(...)` so auth state changes call
`SyncManager.updateSession(userID:)`. From there the sync layer handles owner
switching, local-to-account migration, and network sync.
