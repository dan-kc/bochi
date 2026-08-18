# API Versioning Code Guide

This is a route-contract checklist, not a migration history.

## Current Routes

- Auth routes are unversioned under `/auth/*`.
- Authenticated REST routes are versioned under `/api/v1/*`.
- Sync currently lives at `GET/POST /api/v1/sync`.

Start in:

- `backend/src/router.rs`: route namespaces and auth middleware.
- `ios/bochi/Auth/Services/AuthAPIClient.swift`: unversioned auth calls.
- `ios/bochi/Sync/SyncAPIClient.swift`: `/api/v1/sync` calls.
- `backend/src/api/sync.rs`: sync request/response handling.

## What Versioning Means Here

API version and local SQLite schema version are separate contracts.

- API version: backend wire shape and behavior.
- SQLite migration: local iOS persistence shape in `AppDatabase`.
- Flyway migration: backend database shape.

Do not tie those numbers together.

## Pre-Launch Rule

There are no shipped clients to preserve yet. It is fine to change `/api/v1`
in place when the backend and iOS app are updated together.

Still keep routes under `/api/v1`; do not add new unversioned `/api/*` routes.

## After Launch Rule

Keep `/api/v1` compatible for shipped clients.

Add `/api/v2` when a shipped client would break because a route:

- removes or renames a field
- changes a field's meaning
- starts rejecting requests older clients could validly send
- changes sync conflict/checkpoint semantics in a user-visible way

Additive response fields and optional request fields can stay in the same
version.

## Change Checklist

For backend contract changes:

1. Decide whether this is pre-launch-only or must preserve shipped clients.
2. Update `backend/src/router.rs` only if a new version namespace is needed.
3. Keep version-specific mapping at the HTTP edge.
4. Reuse database/domain logic below the versioned handler where possible.
5. Update iOS clients that call the route.
6. Update backend REST tests and any iOS request/decoding tests.

For iOS persistence changes:

1. Add or update migrations in `ios/bochi/Shared/Persistence/AppDatabase.swift`.
2. Keep the API version unchanged unless the wire contract changed.
3. Run `nix develop -c ios-test`.
