import Foundation
import GRDB

// Sync flow: owns the SQLite tables used by SyncStateStore and the owner-scoped
// stores, including cursor state and dirty record generations.
enum SQLiteValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case null

    var databaseValue: DatabaseValueConvertible? {
        switch self {
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .text(let value):
            return value
        case .null:
            return nil
        }
    }
}

enum AppDatabaseError: Error {
    case openFailed(String)
    case statementFailed(String)
    case transactionFailed(String)
}

typealias AppDatabaseHandle = Database

@MainActor
final class AppDatabase {
    static let shared = AppDatabase()

    private var poolsByPath: [String: DatabasePool] = [:]

    func connection(at url: URL) throws -> DatabasePool {
        if let existing = poolsByPath[url.path] {
            return existing
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        do {
            var configuration = Configuration()
            configuration.foreignKeysEnabled = true

            let pool = try DatabasePool(path: url.path, configuration: configuration)
            try migrate(pool)
            poolsByPath[url.path] = pool
            return pool
        } catch {
            throw AppDatabaseError.openFailed(String(describing: error))
        }
    }

    func transaction<T>(at url: URL, _ body: (AppDatabaseHandle) throws -> T) throws -> T {
        let pool = try connection(at: url)
        do {
            return try pool.write { db in
                try body(db)
            }
        } catch {
            throw AppDatabaseError.transactionFailed(String(describing: error))
        }
    }

    func execute(
        _ sql: String,
        bindings: [SQLiteValue] = [],
        at url: URL
    ) throws {
        let pool = try connection(at: url)
        try pool.write { db in
            try self.execute(sql, bindings: bindings, on: db)
        }
    }

    func execute(
        _ sql: String,
        bindings: [SQLiteValue] = [],
        on database: AppDatabaseHandle
    ) throws {
        do {
            try database.execute(sql: sql, arguments: StatementArguments(bindings.map(\.databaseValue)))
        } catch {
            throw AppDatabaseError.statementFailed(String(describing: error))
        }
    }

    func query<T>(
        _ sql: String,
        bindings: [SQLiteValue] = [],
        at url: URL,
        map: (Row) throws -> T
    ) throws -> [T] {
        let pool = try connection(at: url)
        return try pool.read { db in
            try self.query(sql, bindings: bindings, on: db, map: map)
        }
    }

    func query<T>(
        _ sql: String,
        bindings: [SQLiteValue] = [],
        on database: AppDatabaseHandle,
        map: (Row) throws -> T
    ) throws -> [T] {
        do {
            return try Row.fetchAll(database, sql: sql, arguments: StatementArguments(bindings.map(\.databaseValue))).map(map)
        } catch {
            throw AppDatabaseError.statementFailed(String(describing: error))
        }
    }

    func queryOne<T>(
        _ sql: String,
        bindings: [SQLiteValue] = [],
        at url: URL,
        map: (Row) throws -> T
    ) throws -> T? {
        let pool = try connection(at: url)
        return try pool.read { db in
            try self.queryOne(sql, bindings: bindings, on: db, map: map)
        }
    }

    func queryOne<T>(
        _ sql: String,
        bindings: [SQLiteValue] = [],
        on database: AppDatabaseHandle,
        map: (Row) throws -> T
    ) throws -> T? {
        do {
            guard let row = try Row.fetchOne(database, sql: sql, arguments: StatementArguments(bindings.map(\.databaseValue))) else {
                return nil
            }
            return try map(row)
        } catch {
            throw AppDatabaseError.statementFailed(String(describing: error))
        }
    }

    private func migrate(_ writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_current_schema") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS timers (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    intervals_json TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    server_revision INTEGER
                );

                CREATE INDEX IF NOT EXISTS idx_timers_owner_updated
                ON timers(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS tasks (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    recurring INTEGER NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    base_price INTEGER NOT NULL,
                    due_date REAL,
                    min_daily_frequency REAL,
                    lockout_duration_seconds INTEGER,
                    pinned INTEGER NOT NULL DEFAULT 0,
                    hidden INTEGER NOT NULL DEFAULT 0,
                    timer_mode TEXT,
                    timer_id TEXT,
                    server_revision INTEGER,
                    CHECK (recurring IN (0, 1)),
                    CHECK (recurring = 1 OR (min_daily_frequency IS NULL AND lockout_duration_seconds IS NULL)),
                    CHECK (recurring = 0 OR due_date IS NULL),
                    \(BackendIntegerContract.sqliteNonNegativeCheck("base_price")),
                    \(BackendIntegerContract.sqliteOptionalSignedCheck("lockout_duration_seconds"))
                );

                CREATE INDEX IF NOT EXISTS idx_tasks_owner_recurring_created
                ON tasks(owner_id, recurring, created_at, id);
                CREATE INDEX IF NOT EXISTS idx_tasks_owner_recurring_updated
                ON tasks(owner_id, recurring, updated_at);
                CREATE INDEX IF NOT EXISTS idx_tasks_owner_updated
                ON tasks(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS rewards (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    recurring INTEGER NOT NULL DEFAULT 1,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    max_daily_frequency REAL,
                    base_price INTEGER NOT NULL,
                    lockout_duration_seconds INTEGER,
                    pinned INTEGER NOT NULL DEFAULT 0,
                    hidden INTEGER NOT NULL DEFAULT 0,
                    timer_mode TEXT,
                    timer_id TEXT,
                    server_revision INTEGER,
                    CHECK (recurring IN (0, 1)),
                    CHECK (recurring = 1 OR max_daily_frequency IS NULL),
                    \(BackendIntegerContract.sqliteNonNegativeCheck("base_price")),
                    \(BackendIntegerContract.sqliteOptionalSignedCheck("lockout_duration_seconds"))
                );

                CREATE INDEX IF NOT EXISTS idx_rewards_owner_created
                ON rewards(owner_id, created_at, id);
                CREATE INDEX IF NOT EXISTS idx_rewards_owner_updated
                ON rewards(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS tags (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    color_hex TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    server_revision INTEGER
                );

                CREATE INDEX IF NOT EXISTS idx_tags_owner_created
                ON tags(owner_id, created_at, id);
                CREATE INDEX IF NOT EXISTS idx_tags_owner_updated
                ON tags(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS trades (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    task_id TEXT,
                    recurring_task_id TEXT,
                    reward_id TEXT,
                    source_name TEXT,
                    amount INTEGER NOT NULL,
                    vault_amount_micro INTEGER,
                    adjustment_base_amount INTEGER,
                    one_time_adjustment_multiplier REAL,
                    trade_kind TEXT NOT NULL,
                    vault_interest_hour REAL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    refunds_trade_id TEXT,
                    server_revision INTEGER,
                    \(BackendIntegerContract.sqliteSignedCheck("amount")),
                    \(BackendIntegerContract.sqliteOptionalSignedCheck("adjustment_base_amount")),
                    CHECK (
                        trade_kind IN (
                            'taskCompletion',
                            'recurringTaskCompletion',
                            'rewardPurchase',
                            'vaultDeposit',
                            'vaultInterest',
                            'vaultRewardPurchase'
                        )
                    ),
                    CHECK (
                        (
                            trade_kind = 'taskCompletion'
                            AND task_id IS NOT NULL
                            AND recurring_task_id IS NULL
                            AND reward_id IS NULL
                        )
                        OR (
                            trade_kind = 'recurringTaskCompletion'
                            AND task_id IS NULL
                            AND recurring_task_id IS NOT NULL
                            AND reward_id IS NULL
                        )
                        OR (
                            trade_kind IN ('rewardPurchase', 'vaultRewardPurchase')
                            AND task_id IS NULL
                            AND recurring_task_id IS NULL
                            AND reward_id IS NOT NULL
                        )
                        OR (
                            trade_kind IN ('vaultDeposit', 'vaultInterest')
                            AND task_id IS NULL
                            AND recurring_task_id IS NULL
                            AND reward_id IS NULL
                        )
                    ),
                    CHECK (
                        (
                            trade_kind = 'vaultInterest'
                            AND vault_interest_hour IS NOT NULL
                        )
                        OR (
                            trade_kind != 'vaultInterest'
                            AND vault_interest_hour IS NULL
                        )
                    )
                );

                CREATE INDEX IF NOT EXISTS idx_trades_owner_created
                ON trades(owner_id, created_at, id);
                CREATE INDEX IF NOT EXISTS idx_trades_owner_updated
                ON trades(owner_id, updated_at);
                CREATE INDEX IF NOT EXISTS idx_trades_owner_deleted
                ON trades(owner_id, deleted_at);
                CREATE INDEX IF NOT EXISTS idx_trades_refunds_trade_id
                ON trades(refunds_trade_id);
                CREATE INDEX IF NOT EXISTS idx_trades_owner_trade_kind
                ON trades(owner_id, trade_kind)
                WHERE deleted_at IS NULL;
                CREATE INDEX IF NOT EXISTS idx_trades_owner_task_created
                ON trades(owner_id, task_id, created_at DESC, id DESC);
                CREATE INDEX IF NOT EXISTS idx_trades_owner_recurring_task_created
                ON trades(owner_id, recurring_task_id, created_at DESC, id DESC);
                CREATE INDEX IF NOT EXISTS idx_trades_owner_reward_created
                ON trades(owner_id, reward_id, created_at DESC, id DESC);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_trades_vault_interest_hour
                ON trades(owner_id, vault_interest_hour)
                WHERE deleted_at IS NULL
                    AND trade_kind = 'vaultInterest'
                    AND vault_interest_hour IS NOT NULL;

                CREATE TABLE IF NOT EXISTS task_tags (
                    owner_id TEXT NOT NULL,
                    task_id TEXT NOT NULL,
                    tag_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    server_revision INTEGER,
                    PRIMARY KEY(owner_id, task_id, tag_id)
                );

                CREATE INDEX IF NOT EXISTS idx_task_tags_owner_updated
                ON task_tags(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS recurring_task_tags (
                    owner_id TEXT NOT NULL,
                    recurring_task_id TEXT NOT NULL,
                    tag_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    server_revision INTEGER,
                    PRIMARY KEY(owner_id, recurring_task_id, tag_id)
                );

                CREATE INDEX IF NOT EXISTS idx_recurring_task_tags_owner_updated
                ON recurring_task_tags(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS reward_tags (
                    owner_id TEXT NOT NULL,
                    reward_id TEXT NOT NULL,
                    tag_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    server_revision INTEGER,
                    PRIMARY KEY(owner_id, reward_id, tag_id)
                );

                CREATE INDEX IF NOT EXISTS idx_reward_tags_owner_updated
                ON reward_tags(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS task_task_dependencies (
                    owner_id TEXT NOT NULL,
                    task_id TEXT NOT NULL,
                    depends_on_task_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    server_revision INTEGER,
                    PRIMARY KEY(owner_id, task_id, depends_on_task_id)
                );

                CREATE INDEX IF NOT EXISTS idx_task_task_dependencies_owner_updated
                ON task_task_dependencies(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS task_recurring_task_dependencies (
                    owner_id TEXT NOT NULL,
                    task_id TEXT NOT NULL,
                    recurring_task_id TEXT NOT NULL,
                    required_completions INTEGER NOT NULL,
                    baseline_completion_count INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    server_revision INTEGER,
                    PRIMARY KEY(owner_id, task_id, recurring_task_id),
                    \(BackendIntegerContract.sqlitePositiveCheck("required_completions")),
                    \(BackendIntegerContract.sqliteNonNegativeCheck("baseline_completion_count"))
                );

                CREATE INDEX IF NOT EXISTS idx_task_recurring_task_dependencies_owner_updated
                ON task_recurring_task_dependencies(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS reward_task_dependencies (
                    owner_id TEXT NOT NULL,
                    reward_id TEXT NOT NULL,
                    depends_on_task_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    server_revision INTEGER,
                    PRIMARY KEY(owner_id, reward_id, depends_on_task_id)
                );

                CREATE INDEX IF NOT EXISTS idx_reward_task_dependencies_owner_updated
                ON reward_task_dependencies(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS reward_recurring_task_dependencies (
                    owner_id TEXT NOT NULL,
                    reward_id TEXT NOT NULL,
                    recurring_task_id TEXT NOT NULL,
                    required_completions INTEGER NOT NULL,
                    baseline_completion_count INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    server_revision INTEGER,
                    PRIMARY KEY(owner_id, reward_id, recurring_task_id),
                    \(BackendIntegerContract.sqlitePositiveCheck("required_completions")),
                    \(BackendIntegerContract.sqliteNonNegativeCheck("baseline_completion_count"))
                );

                CREATE INDEX IF NOT EXISTS idx_reward_recurring_task_dependencies_owner_updated
                ON reward_recurring_task_dependencies(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS reminders (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    task_id TEXT,
                    recurring_task_id TEXT,
                    scheduled_at REAL NOT NULL,
                    repeat_value INTEGER,
                    repeat_unit TEXT,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    CHECK (
                        (CASE WHEN task_id IS NOT NULL THEN 1 ELSE 0 END) +
                        (CASE WHEN recurring_task_id IS NOT NULL THEN 1 ELSE 0 END) = 1
                    )
                );

                CREATE INDEX IF NOT EXISTS idx_reminders_owner_scheduled
                ON reminders(owner_id, scheduled_at, id);
                CREATE INDEX IF NOT EXISTS idx_reminders_owner_updated
                ON reminders(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS user_settings (
                    owner_id TEXT PRIMARY KEY,
                    theme_palette_main TEXT NOT NULL DEFAULT 'porcelain',
                    theme_palette_accent TEXT NOT NULL DEFAULT 'semantic'
                );

                CREATE TABLE IF NOT EXISTS list_preferences (
                    owner_id TEXT NOT NULL,
                    scope TEXT NOT NULL,
                    sort TEXT NOT NULL,
                    selected_tag_ids_json TEXT NOT NULL DEFAULT '[]',
                    hidden_status_filters_json TEXT NOT NULL DEFAULT '[]',
                    hidden_tag_ids_json TEXT NOT NULL DEFAULT '[]',
                    PRIMARY KEY(owner_id, scope)
                );

                CREATE TABLE IF NOT EXISTS balance_projections (
                    owner_id TEXT PRIMARY KEY,
                    balance INTEGER NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS sync_state (
                    user_id TEXT PRIMARY KEY,
                    last_sync_server_time REAL,
                    last_full_sync_at REAL,
                    full_sync_required INTEGER NOT NULL DEFAULT 1,
                    last_sync_cursor TEXT,
                    last_mutation_generation INTEGER NOT NULL DEFAULT 0
                );

                CREATE TABLE IF NOT EXISTS dirty_records (
                    user_id TEXT NOT NULL,
                    entity_kind TEXT NOT NULL,
                    record_id TEXT NOT NULL,
                    mutation_generation INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY(user_id, entity_kind, record_id)
                );

                CREATE INDEX IF NOT EXISTS idx_dirty_records_user_kind
                ON dirty_records(user_id, entity_kind);
                CREATE INDEX IF NOT EXISTS idx_dirty_records_user_kind_generation
                ON dirty_records(user_id, entity_kind, mutation_generation);

                CREATE TABLE IF NOT EXISTS dirty_flags (
                    user_id TEXT NOT NULL,
                    entity_kind TEXT NOT NULL,
                    mutation_generation INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY(user_id, entity_kind)
                );
                """)
        }

        try migrator.migrate(writer)
    }
}

enum SQLiteColumn {
    static func text(_ row: Row, index: Int) -> String {
        row[index]
    }

    static func optionalText(_ row: Row, index: Int) -> String? {
        row[index]
    }

    static func int(_ row: Row, index: Int) -> Int {
        row[index]
    }

    static func optionalInt(_ row: Row, index: Int) -> Int? {
        row[index]
    }

    static func optionalInt64(_ row: Row, index: Int) -> Int64? {
        row[index]
    }

    static func double(_ row: Row, index: Int) -> Double {
        row[index]
    }

    static func optionalDouble(_ row: Row, index: Int) -> Double? {
        row[index]
    }

    static func bool(_ row: Row, index: Int) -> Bool {
        let value: Int = row[index]
        return value != 0
    }

    static func date(_ row: Row, index: Int) -> Date {
        Date(timeIntervalSince1970: double(row, index: index))
    }

    static func optionalDate(_ row: Row, index: Int) -> Date? {
        guard let value: Double = row[index] else { return nil }
        return Date(timeIntervalSince1970: value)
    }
}
