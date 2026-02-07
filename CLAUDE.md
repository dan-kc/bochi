Tofustash is a gamified productivity tool to handle your habits. It is themed on personal finance and the stock exchange. You earn "soy" that is the in game currency. It is awarded for completing habits, and it is spent on rewards like "eat a chocolate bar".

When making changes across database/backend/frontend always work in the following order:
- Change tests if any
- Change create migrations if any
- Change backend code until backend tests pass if any
- Change frontend tests if any
- Change frontend

## Frontend

A local-first React Native application for Web, Android and IOS.

## Backend

A rust axum REST server.

## Database

Postgresql, with migrations are handled with flyway.

## Development

Local dev commands are found in scripts.nix.
Logs for all processes can be found in logs/

### Nix Devshell Commands

**IMPORTANT:** Always run these commands from the project root. Do NOT cd into frontend/ - Node is only available through the nix devshell wrappers.

#### Frontend (use from project root)

- `npm run lint` - Run ESLint on frontend code
- `npm run typecheck` - Run TypeScript type checking
- `npm run web` - Start frontend web dev server
- `npm <command>` - Run any npm command in frontend directory

#### Backend

- `run` - Start backend with proper env vars (wraps cargo run)
- `t` - Run backend tests (sets up test DB, runs cargo test)

#### Services

- `start` - Start all services (postgres, backend, frontend, adminer, lspmux)
- `start --force` - Force restart all services
- `stop` - Stop all services
- `status` - Show status of all services

#### Database

- `schema <table>` - Display schema of a database table
- `fw <db> migrate` - Run Flyway migrations
- `seed` - Load fixture data into tofustash database
- `clean <db>` - Truncate all tables in a database
- `nuke <db>` - Drop and recreate database, apply migrations
