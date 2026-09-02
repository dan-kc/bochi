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

- `start` verifies the configured Tailscale devices, then starts loopback-only PostgreSQL, the Tailscale-only backend, loopback-only Adminer, and LSP mux. Use `start --force` or `start -f` to stop and restart everything.
- `stop` stops PostgreSQL, backend, Adminer, and LSP mux.
- `status` prints compact running state and endpoint details for local services, including the LSP mux PID. Use `status --verbose` to include the LSP mux root, socket, and log details.
- `start-postgres` starts only PostgreSQL and ensures the configured app and test databases exist.
- `adminer` starts Adminer directly.
- `kp` kills only the backend process tracked by this repo.

## Backend

- `t [cargo-test-args...]` cleans the test database, switches the backend to the test database, and runs `cargo test`.
- `run [cargo-run-args...]` verifies the configured Tailscale devices, then runs the Tailscale-only backend with the app database and required environment variables.
- `clean <database_name>` truncates app tables in the chosen database.
- `seed` cleans the development database and loads `dev-seed.sql`, including the Alice account available from the Debug app's local sign-in button.
- `reset-subscriptions` deletes local premium/subscription state from the development database without deleting users or app data. Use after clearing StoreKit transactions in Xcode.

## Database

- `schema` lists tables in the development database.
- `schema <table_name>` shows detailed schema information for a table.
- `fw <database_name> <flyway-args...>` runs Flyway against the selected database. The wrapper always treats the first argument as the database name, so use `fw bochi migrate` for the development database and `fw bochi_test migrate` for the test database.
- `nuke <database_name>` kills the backend, drops and recreates the chosen database, then applies migrations.

Do not edit existing migration files. Add a new migration when schema changes are needed.

## iOS

- `ios-test [test-name...]` runs Swift unit tests on `iPhone 17 Pro`. With test names, it runs only those tests.
- Debug iOS builds inherit the Mac API host from `config/local-development.xcconfig`; there is no IP update command.

## Infrastructure

- `tf <tofu-args...>` runs OpenTofu from `./infra`.
