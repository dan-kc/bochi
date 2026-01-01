## Available Commands

### Database Management

#### `clean <database_name>`

Truncates all tables in the provided database.

- **Usage**: `clean tofustash` or `clean tofustash_test`
- **What it does**: Removes all data from tables (refresh_tokens, tags, task_dependencies, task_tags, tasks, trades, users) using CASCADE

#### `nuke <database_name>`

Drops and recreates the provided database, then applies migrations.

- **Usage**: `nuke tofustash` or `nuke tofustash_test`
- **What it does**:
  1. Kills any running tofustash processes
  2. Drops the existing database
  3. Creates a fresh database
  4. Runs Flyway migrations

#### `schema <table_name>`

Displays the schema of a database table.

- **Usage**: `schema users` or `schema tasks`
- **What it does**: Shows detailed table structure using PostgreSQL's `\d+` command

### Development Environment

#### `start`

Starts the complete development environment.

- **Usage**: `start`
- **What it does**:
  1. Stops any existing services
  2. Starts PostgreSQL
  3. Starts Adminer (database UI)
  4. Starts Loki (log aggregation)
  5. Starts Promtail (log shipper)
  6. Starts Grafana (observability dashboard)

#### `stop`

Stops all development services.

- **Usage**: `stop`
- **What it does**: Stops PostgreSQL, Adminer, Loki, Promtail, and Grafana

### Application Commands

#### `run [cargo args]`

Runs the application with proper environment variables.

- **Usage**: `run` or `run --release`
- **What it does**: Executes `cargo run` with database credentials, JWT keys, and logging configuration

#### `t [test args]`

Runs tests with proper test environment setup.

- **Usage**: `t` or `t test_register_success`
- **What it does**:
  1. Cleans the test database
  2. Runs `cargo test` with test database configuration

### Tools

#### `fw [database_name] <flyway command>`

Flyway migration wrapper.

- **Usage**: `fw tofustash migrate` or `fw tofustash_test info`
- **What it does**: Runs Flyway commands against specified database (defaults to 'tofustash')

#### `tf <terraform command>`

Terraform/OpenTofu wrapper.

- **Usage**: `tf plan` or `tf apply`
- **What it does**: Runs Terraform/OpenTofu commands in the `./infra` directory

#### `ra`

Starts ra-multiplex server for rust-analyzer.

- **Usage**: `ra`
- **What it does**: Starts a multiplexed rust-analyzer server for better IDE performance

## Notes

### Do no do until launch:

- Monitoring (prometheus for application level monitoring, cloudwatch for OS monitoring)
