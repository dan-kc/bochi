# API Versioning And Upgrades

This project now versions backend REST routes under `/api/vN`.

Current baseline:

- sync lives at `/api/v1/sync`
- the rest of the authenticated REST surface also lives under `/api/v1/*`
- auth remains unversioned at `/auth/*`

## Why we version

The iOS app has two independent upgrade axes:

- backend API contract
- local SQLite schema

Those are related, but they should not share one version number.

An app build may:

- stay on API `v1` while adding several local SQLite migrations
- move to API `v2` without changing every local table

Treat them as separate contracts so the server can evolve without guessing what a local database can handle.

## Versioning rules

Use the same API version when a change is additive:

- adding an optional request field
- adding a response field that old clients can ignore safely
- adding a new endpoint inside the same version namespace
- changing backend internals without changing request or response behavior

Cut a new API version when a change is breaking:

- removing a response field
- renaming a field
- changing field meaning
- changing validation in a way that can reject requests older clients used to send
- changing sync conflict semantics in a way that can alter user-visible results

## Route policy

When introducing a new version:

1. add a new router namespace such as `/api/v2`
2. keep version-specific request and response mapping at the HTTP edge
3. reuse shared domain and database logic underneath when possible
4. update the iOS client to call the new route explicitly
5. add or update backend integration tests for the new namespace
6. update docs that describe the live contract

Do not point new clients at unversioned `/api/*` routes.

## SQLite migration policy

The iOS SQLite migrator in `AppDatabase` is the source of truth for local schema upgrades.

When a new backend feature depends on new local storage:

1. add the SQLite migration first
2. keep the app on the existing API version if the wire contract is still compatible
3. only cut a new API version if the wire contract itself becomes incompatible

Do not couple:

- Flyway migration numbers
- GRDB migration names
- API version numbers

Those three sequences solve different problems.

## Recommended rollout process

For backend changes:

1. decide whether the wire contract is additive or breaking
2. if breaking, add `/api/v{next}` routes and tests before changing client code
3. keep shared business logic below the versioned handlers where practical
4. update docs and the iOS client in the same change when there are no live users

For iOS changes:

1. add local SQLite migrations when the device needs new persistent state
2. update the live API client to the intended versioned route
3. add or update unit tests for request behavior when the client contract changes
4. run `ios-test`

## Current expectation

Because there are no live users yet, the repository does not keep an alias from `/api/sync` to `/api/v1/sync`.

If that changes later, preserve old versioned routes for shipped clients and sunset them intentionally based on observed usage, not by replacing them in place.
