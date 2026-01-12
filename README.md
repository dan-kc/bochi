Tofustash is a gamefied productivity tool to handle your habits and todos. It is themed on personal finance and the stock exchange. You earn "soy" that is the in game currency. It is awarded for completing tasks (habits or todos), and it is spent on rewards like "eat a chocolcate bar".

## Frontend

A local-first React Native application for Web, Android and IOS.

## Backend

A rust axum graphql server.

## Database

Postgresql, with migrations are handled with flyway.

## Sync Architecture

The app uses a unified sync system for offline-first operation:

- **Single endpoint**: All entity types (tasks, trades) sync through one GraphQL `sync` query/mutation
- **Atomic transactions**: Push operations process all entities in a single database transaction
- **Dependency ordering**: Tasks are processed before trades to handle foreign key constraints
- **Conflict resolution**: Last-write-wins based on `updated_at` timestamps
- **Incremental sync**: Uses `since` parameter to fetch only changes after last sync
- **Full sync**: Automatically triggered every 24 hours to ensure consistency

Client-side state is stored in a single `tofustash_sync_state` JSON blob containing the last sync timestamp and dirty entity IDs.

## Development

Local dev commands are found in scripts.nix.
Logs for all processes can be found in logs/
