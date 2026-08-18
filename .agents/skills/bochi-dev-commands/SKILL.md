---
name: bochi-dev-commands
description: Use when running Bochi repo helper commands for development services, backend tests, database schema/migrations, iOS builds/tests, or infrastructure.
---

# Bochi Dev Commands

Use this skill before running repository-specific commands. The helper commands are defined in `scripts.nix` and should be run through the Nix devshell:

```sh
nix develop -c <command>
```

Regular shell inspection commands such as `rg`, `sed`, `git`, and `ls` do not need the devshell unless they depend on project-specific tooling.

## Development Environment

- `start` starts the local development stack: PostgreSQL, backend, Adminer, and LSP mux. Use `start --force` or `start -f` to stop and restart everything.
- `stop` stops PostgreSQL, backend, Adminer, and LSP mux.
- `status` prints the running state and ports for local services.
- `start-postgres` starts only PostgreSQL and ensures the configured app and test databases exist.
- `adminer` starts Adminer directly.
- `kp` kills only the backend process tracked by this repo.

## Backend

- `t [cargo-test-args...]` cleans the test database, switches the backend to the test database, and runs `cargo test`.
- `run [cargo-run-args...]` runs the backend with the app database and required environment variables.
- `clean <database_name>` truncates app tables in the chosen database.
- `seed` cleans the development database and loads `dev-seed.sql`.
- `reset-subscriptions` deletes local premium/subscription state from the development database without deleting users or app data. Use after clearing StoreKit transactions in Xcode.

## Database

- `schema` lists tables in the development database.
- `schema <table_name>` shows detailed schema information for a table.
- `fw <database_name> <flyway-args...>` runs Flyway against the selected database. The wrapper always treats the first argument as the database name, so use `fw bochi migrate` for the development database and `fw bochi_test migrate` for the test database.
- `nuke <database_name>` kills the backend, drops and recreates the chosen database, then applies migrations.

Do not edit existing migration files. Add a new migration when schema changes are needed.

## iOS

- `ios-test [test-name...]` runs Swift unit tests on `iPhone 17 Pro`. With test names, it runs only those tests.
- `update-ip [ip_address]` updates the Debug iOS build setting for the local API host. With no argument, it detects the active Mac IPv4 address.

## Infrastructure

- `tf <tofu-args...>` runs OpenTofu from `./infra`.
