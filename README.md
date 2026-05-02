Tofustash is a gamified productivity tool to handle your habits. It is themed on personal finance and the stock exchange. You earn "tofu" that is the in game currency. It is awarded for completing habits, and it is spent on rewards like "eat a chocolate bar".

## Backend

A rust axum graphql server.

## Database

Postgresql, with migrations are handled with flyway.

## Sync Architecture

The app uses a unified sync system for offline-first operation:

- **Single endpoint**: All entity types (habits, trades) sync through one REST `/api/v1/sync` endpoint
- **Atomic transactions**: Push operations process all entities in a single database transaction
- **Dependency ordering**: Habits are processed before trades to handle foreign key constraints
- **Conflict resolution**: Last-write-wins based on `updated_at` timestamps
- **Snapshot pull cursor**: `GET /api/v1/sync` reads from one repeatable-read snapshot and returns an opaque `serverCursor`
- **Incremental sync**: Uses `cursor` to fetch only changes after the last acknowledged snapshot
- **Full sync**: Automatically triggered every 24 hours to ensure consistency

Client-side sync metadata now lives in SQLite tables:

- `sync_state` for per-user checkpoints and full-sync flags
- `dirty_records` for versioned dirty row ids
- `dirty_flags` for versioned dirty singleton settings

Signed-in local writes persist domain rows and dirty metadata in the same SQLite transaction so a crash cannot leave a durable row behind without a matching sync marker.

## Development

Local dev commands are found in scripts.nix.
Logs for all processes can be found in logs/
