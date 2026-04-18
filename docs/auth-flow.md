# Auth Flow

## Purpose

This document explains how authentication, account ownership, Apple purchase restore, and premium entitlement work across the iOS app and backend.

The important rule is:

- account ownership and premium entitlement are separate facts

A user can be:

- signed out, with no backend account in use on this device
- signed in, with a backend account
- locally entitled to Apple premium on this device
- entitled to premium through the backend account

Those facts overlap, but they are not the same thing. The implementation is built around keeping them separate until an explicit linking step happens.

## Design Goals

- A user can use the app without creating an account.
- Local-only use should not require a backend user row or session.
- Creating or signing into an account enables sync and backend-owned data.
- Restoring an Apple purchase should never invent or guess an app account.
- Premium can exist temporarily on-device before it is linked to an account.
- Web billing and Apple billing must both be representable.
- Cancellation and expiry should remove entitlement without deleting the account or synced data.

## Core Model

There are three different sources of truth:

1. StoreKit on the device
   - Answers whether this Apple ID currently has a valid in-app purchase entitlement on this device.
   - This is where `Restore Apple Purchase` gets its answer.

2. Backend account state
   - Answers which backend user is signed in and which subscription state is linked to that account.
   - This is where `/auth/me` gets its answer.

3. Local app session state
   - Combines StoreKit state and backend account state into a single user-facing SwiftUI state.

The app should derive display state from those facts instead of persisting one giant enum in the backend.

## Implemented iOS Session States

The iOS app currently derives these states in `AuthManager`:

- `signedOutFree`
  - No signed-in backend account.
  - No local Apple entitlement.
  - User is in local-only free mode.

- `signedOutPremiumRestored`
  - No signed-in backend account.
  - Local Apple entitlement exists on this device.
  - Premium is visible locally, but sync is still unavailable.

- `signedInFree`
  - Signed into a backend account.
  - Account is not currently premium-entitled.

- `signedInPremiumApple`
  - Signed into a backend account.
  - Backend reports Apple-linked premium entitlement.

- `signedInPremiumWeb`
  - Signed into a backend account.
  - Backend reports web-linked premium entitlement.

- `signedInLapsed`
  - Signed into a backend account.
  - Backend reports expired, revoked, or billing-issue premium state.
  - Account and sync still exist, but premium is locked.

These are user-facing states only. The backend does not store them as a single enum.

## Backend Account State

The backend stores durable account/subscription facts on `users`:

- `email`
- `subscription_source`
  - `NULL`
  - `apple`
  - `web`
- `subscription_status`
  - `none`
  - `active`
  - `grace_period`
  - `billing_retry`
  - `expired`
  - `revoked`
- `subscription_expires_at`
- `app_store_original_transaction_id`
- `external_billing_customer_id`

From that, the backend derives whether the account is entitled.

Current entitlement rule:

- `active` and `grace_period` are entitled
- `none`, `billing_retry`, `expired`, and `revoked` are not entitled

The backend exposes that derived view through `/auth/me`.

## Active Endpoints

### `POST /auth/register`

Creates a normal backend account and returns auth tokens.

Important behaviour:

- This does not automatically create premium entitlement.
- If the device already has a restored Apple entitlement, the iOS app may immediately follow registration with `POST /auth/link-apple-subscription`.

### `POST /auth/login`

Signs into an existing backend account and returns auth tokens.

Important behaviour:

- This does not itself restore Apple purchases.
- If the device already has a local Apple entitlement, the iOS app may immediately follow login with `POST /auth/link-apple-subscription`.

### `POST /auth/refresh-tokens`

Refreshes the backend session tokens.

Important behaviour:

- After refresh, iOS calls `/auth/me` to rebuild the signed-in state.

### `GET /auth/me`

Returns the signed-in account’s auth/subscription view:

- `email`
- `subscriptionSource`
- `subscriptionStatus`
- `isEntitled`
- `subscriptionExpiresAt`

This is the canonical backend truth for:

- whether the user is signed in
- what premium state belongs to that account
- whether the premium source is Apple or web
- whether the account is lapsed

### `POST /auth/link-apple-subscription`

Links a restored Apple purchase to the currently signed-in backend account.

Request fields:

- `originalTransactionId`
- `subscriptionExpiresAt` nullable

Important behaviour:

- Requires authentication.
- If the Apple purchase is already linked to a different account, the endpoint returns `409 SUBSCRIPTION_ALREADY_LINKED`.
- If the purchase is not yet linked, the backend stores the Apple transaction ID on the current user and marks the account as Apple premium.
- The endpoint returns the same shape as `/auth/me`.

This is the endpoint that turns:

- signed-in account + local restored Apple entitlement

into:

- signed-in Apple premium account

## Implemented iOS Flows

### App Launch

On launch, `AuthManager.bootstrap()` does this:

1. Ask StoreKit for the current local Apple entitlement.
2. Check whether backend tokens exist in secure storage.
3. If no backend tokens exist:
   - enter `signedOutFree` or `signedOutPremiumRestored`
4. If backend tokens exist:
   - try refresh
   - on success, call `/auth/me`
   - derive the signed-in state from the backend response
5. If refresh returns `401`:
   - clear backend tokens
   - fall back to the signed-out local state

This lets a signed-out user still land in premium-restored mode before any network call.

### Register While Signed Out

When a user creates an account from local-only mode:

1. iOS calls `POST /auth/register`
2. iOS stores the tokens
3. iOS calls `GET /auth/me`
4. If a local Apple entitlement already exists and the backend account is not yet entitled:
   - iOS calls `POST /auth/link-apple-subscription`

If linking succeeds:

- the user lands in `signedInPremiumApple`

If linking fails:

- the registration still succeeds
- the account remains signed in
- the device-level Apple entitlement remains visible as unlinked

### Login While Signed Out

When a user logs into an existing account:

1. iOS calls `POST /auth/login`
2. iOS stores the tokens
3. iOS calls `GET /auth/me`
4. If a local Apple entitlement already exists and the backend account is not yet entitled:
   - iOS calls `POST /auth/link-apple-subscription`

This handles the common case where:

- the user restored first while signed out
- then later signed into the account that should own the Apple purchase

### Restore Apple Purchase While Signed Out

When the user taps `Restore Apple Purchase` while signed out:

1. iOS calls StoreKit `AppStore.sync()`
2. iOS refreshes local Apple entitlement state
3. If StoreKit reports an active entitlement:
   - the app enters `signedOutPremiumRestored`
4. No backend account is created
5. No backend entitlement is linked yet

This is intentional.

StoreKit can answer:

- "This Apple ID owns this purchase"

It cannot safely answer:

- "Which backend app account should own the synced data for this purchase"

### Restore Apple Purchase While Signed In

When the user taps `Restore Apple Purchase` while already signed in:

1. iOS calls StoreKit restore
2. iOS refreshes local Apple entitlement state
3. If there is an active Apple entitlement and the backend account is not yet entitled:
   - iOS calls `POST /auth/link-apple-subscription`

If linking succeeds:

- the user becomes `signedInPremiumApple`

If linking fails:

- the restore still succeeded locally
- the account stays signed in
- the device may still show an unlinked local Apple entitlement state
- the UI should explain that premium on this device is not linked to this account yet

### Logout

Logging out only clears the backend session.

It does not:

- delete local data
- remove StoreKit entitlement from the device

So if the device still has an active Apple entitlement, logout leads to:

- `signedOutPremiumRestored`

instead of:

- `signedOutFree`

## Why Restore Does Not Auto-Create an Account

This is the core product-safety rule.

If a signed-out restore automatically created or chose an account, the app would be guessing:

- which email identity the user wants
- whether they already have an existing app account
- whether this device is being used by the same person as another device
- where synced data should live

That guess is not reliable.

So the implementation deliberately separates:

- restore purchase
- sign in / sign up
- link purchase to account

## Account Ownership vs Premium Entitlement

These questions are answered by different systems:

- "Which account is signed in?"
  - backend auth

- "Does this device currently have a valid Apple purchase?"
  - StoreKit

- "Which backend account owns premium sync access?"
  - backend subscription linking/state

This separation is what allows:

- signed-out premium restored mode
- web subscriptions
- Apple purchase conflict detection
- lapsed accounts that still keep their synced data

## Edge Cases

### 1. Restore While Signed Out, Then Sign Into Existing Account

Expected behaviour:

- restore grants device-level premium only
- no account is created
- later login may call `POST /auth/link-apple-subscription`
- if the purchase is not already linked elsewhere, the account becomes `signedInPremiumApple`

### 2. Restore While Signed Out, Then Create New Account

Expected behaviour:

- restore grants device-level premium only
- registration creates a backend account
- iOS then links the Apple purchase to that new account

### 3. Restore While Signed In

Expected behaviour:

- the user remains the same backend user
- restore should not create a second account
- successful linking upgrades the same account into Apple premium

### 4. Apple Purchase Already Linked to Another Account

Expected behaviour:

- backend returns `409 SUBSCRIPTION_ALREADY_LINKED`
- premium ownership does not silently move
- the signed-in account stays as-is
- the UI should point the user toward support or manual resolution if needed

This is safer than silently transferring a purchase across accounts.

### 5. User Has Web Premium, No Apple Premium

Expected behaviour:

- `/auth/me` reports `subscriptionSource = web`
- signed-in state becomes `signedInPremiumWeb`
- `Restore Apple Purchase` may legitimately do nothing

### 6. User Has Apple Premium on Another Device, Signs In Here

Expected behaviour:

- if the backend account was already linked earlier, `/auth/me` should already report Apple premium
- the user becomes `signedInPremiumApple` even before a local restore

This is the difference between:

- backend-linked account entitlement

and:

- device-local StoreKit restore state

### 7. User Cancels Auto-Renew

Cancellation is not immediate loss of access.

Expected behaviour:

- the subscription remains active until the paid-through date
- backend should continue to report entitled state until expiry
- iOS should continue to show premium active until `subscriptionExpiresAt`

### 8. Subscription Expires

Expected behaviour:

- account stays signed in
- sync stays available
- premium features lock
- signed-in state becomes `signedInLapsed`
- existing synced data is not deleted

This is a downgrade, not an account deletion.

### 9. Billing Retry / Grace Period

Current state model supports:

- `grace_period`
- `billing_retry`

Expected behaviour:

- `grace_period` remains entitled
- `billing_retry` is considered lapsed in the current app state mapping

If product behaviour changes later, the UI state mapping can change without redesigning auth.

### 10. Refund / Revocation

Expected behaviour:

- backend reports `revoked`
- the account remains
- premium entitlement is removed
- signed-in state becomes `signedInLapsed`

### 11. `/auth/me` Temporarily Fails Right After Login/Register/Refresh

Expected behaviour:

- the user should stay signed in if tokens were just obtained successfully
- iOS uses a provisional signed-in account state
- the app should not log the user out just because `/auth/me` had a transient failure

### 12. Restore Succeeds Locally But Linking Fails

Expected behaviour:

- local Apple entitlement still exists
- backend account may still be free
- the user can keep using the device-level entitlement state
- the app should surface that the purchase is unlinked rather than pretending the backend link happened

## What Is Local-Only vs Backend-Persisted

Local-only:

- signed-out usage
- StoreKit restore result on this device before linking
- temporary app session state

Backend-persisted:

- registered account identity
- auth session tokens
- synced data
- linked subscription source/status
- Apple original transaction ownership

## What Was Removed

The app and backend no longer use backend anonymous accounts for the iOS flow.

Removed model:

- backend-created anonymous user rows
- claim-anonymous-account flow
- backend device ID auth

Current model:

- signed-out means local-only
- account creation starts backend ownership
- Apple restore can exist first, but linking is explicit

## Current Limitations

This document describes the current implementation, not every possible future billing flow.

In particular:

- Apple linking currently relies on the client providing restore metadata to the backend
- a richer server-side verification pipeline may be added later
- web billing exists in the state model, but its linking/management flow is outside this document

## Files To Read

If you are changing this system, start here:

- iOS state machine: [ios/tofustash/Auth/AuthManager.swift](/Users/danielcox/projects/tofustash/ios/tofustash/Auth/AuthManager.swift:1)
- iOS auth API client: [ios/tofustash/Auth/Services/AuthAPIClient.swift](/Users/danielcox/projects/tofustash/ios/tofustash/Auth/Services/AuthAPIClient.swift:1)
- iOS StoreKit entitlement client: [ios/tofustash/Auth/Services/AppleEntitlementClient.swift](/Users/danielcox/projects/tofustash/ios/tofustash/Auth/Services/AppleEntitlementClient.swift:1)
- iOS settings/account UX: [ios/tofustash/SettingsView.swift](/Users/danielcox/projects/tofustash/ios/tofustash/SettingsView.swift:1)
- backend auth routes: [backend/src/routes.rs](/Users/danielcox/projects/tofustash/backend/src/routes.rs:1)
- backend auth router: [backend/src/router.rs](/Users/danielcox/projects/tofustash/backend/src/router.rs:1)
- backend account queries: [backend/src/database.rs](/Users/danielcox/projects/tofustash/backend/src/database.rs:1)
- backend auth tests: [backend/tests/auth](/Users/danielcox/projects/tofustash/backend/tests/auth)
- iOS auth tests: [ios/tofustashTests/AuthManagerTests.swift](/Users/danielcox/projects/tofustash/ios/tofustashTests/AuthManagerTests.swift:1)
