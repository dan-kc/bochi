import Foundation
import GRDB

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
        migrator.registerMigration("v1_initial_sqlite_store") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS habits (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    min_daily_frequency REAL,
                    difficulty_tier TEXT,
                    duration_seconds INTEGER,
                    lockout_duration_seconds INTEGER,
                    skip_consequence INTEGER
                );

                CREATE INDEX IF NOT EXISTS idx_habits_owner_created
                ON habits(owner_id, created_at, id);
                CREATE INDEX IF NOT EXISTS idx_habits_owner_updated
                ON habits(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS rewards (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    max_daily_frequency REAL,
                    damage_tier TEXT
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
                    deleted_at REAL
                );

                CREATE INDEX IF NOT EXISTS idx_tags_owner_created
                ON tags(owner_id, created_at, id);
                CREATE INDEX IF NOT EXISTS idx_tags_owner_updated
                ON tags(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS trades (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    habit_id TEXT,
                    reward_id TEXT,
                    amount INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    CHECK ((habit_id IS NOT NULL) != (reward_id IS NOT NULL))
                );

                CREATE INDEX IF NOT EXISTS idx_trades_owner_created
                ON trades(owner_id, created_at, id);
                CREATE INDEX IF NOT EXISTS idx_trades_owner_updated
                ON trades(owner_id, updated_at);
                CREATE INDEX IF NOT EXISTS idx_trades_owner_deleted
                ON trades(owner_id, deleted_at);

                CREATE TABLE IF NOT EXISTS habit_tags (
                    owner_id TEXT NOT NULL,
                    habit_id TEXT NOT NULL,
                    tag_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    PRIMARY KEY(owner_id, habit_id, tag_id)
                );

                CREATE INDEX IF NOT EXISTS idx_habit_tags_owner_updated
                ON habit_tags(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS reward_tags (
                    owner_id TEXT NOT NULL,
                    reward_id TEXT NOT NULL,
                    tag_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    PRIMARY KEY(owner_id, reward_id, tag_id)
                );

                CREATE INDEX IF NOT EXISTS idx_reward_tags_owner_updated
                ON reward_tags(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS user_settings (
                    owner_id TEXT PRIMARY KEY,
                    general_difficulty REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS list_preferences (
                    owner_id TEXT NOT NULL,
                    scope TEXT NOT NULL,
                    sort TEXT NOT NULL,
                    selected_tag_ids_json TEXT NOT NULL,
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
                    full_sync_required INTEGER NOT NULL DEFAULT 1
                );

                CREATE TABLE IF NOT EXISTS dirty_records (
                    user_id TEXT NOT NULL,
                    entity_kind TEXT NOT NULL,
                    record_id TEXT NOT NULL,
                    PRIMARY KEY(user_id, entity_kind, record_id)
                );

                CREATE INDEX IF NOT EXISTS idx_dirty_records_user_kind
                ON dirty_records(user_id, entity_kind);

                CREATE TABLE IF NOT EXISTS dirty_flags (
                    user_id TEXT NOT NULL,
                    entity_kind TEXT NOT NULL,
                    PRIMARY KEY(user_id, entity_kind)
                );
                """)
        }

        migrator.registerMigration("v2_sync_atomicity") { db in
            try db.execute(sql: """
                ALTER TABLE sync_state ADD COLUMN last_sync_cursor TEXT;
                ALTER TABLE sync_state ADD COLUMN last_mutation_generation INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE dirty_records ADD COLUMN mutation_generation INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE dirty_flags ADD COLUMN mutation_generation INTEGER NOT NULL DEFAULT 0;
                CREATE INDEX IF NOT EXISTS idx_dirty_records_user_kind_generation
                ON dirty_records(user_id, entity_kind, mutation_generation);
            """)
        }

        migrator.registerMigration("v3_tasks") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS tasks (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    completed_at REAL,
                    difficulty_tier TEXT,
                    duration_seconds INTEGER,
                    skip_consequence INTEGER,
                    due_date REAL
                );

                CREATE INDEX IF NOT EXISTS idx_tasks_owner_created
                ON tasks(owner_id, created_at, id);
                CREATE INDEX IF NOT EXISTS idx_tasks_owner_updated
                ON tasks(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS task_tags (
                    owner_id TEXT NOT NULL,
                    task_id TEXT NOT NULL,
                    tag_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    PRIMARY KEY(owner_id, task_id, tag_id)
                );

                CREATE INDEX IF NOT EXISTS idx_task_tags_owner_updated
                ON task_tags(owner_id, updated_at);

                ALTER TABLE trades ADD COLUMN task_id TEXT;

                CREATE TABLE trades_v3 (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    task_id TEXT,
                    habit_id TEXT,
                    reward_id TEXT,
                    amount INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    CHECK (
                        (CASE WHEN task_id IS NOT NULL THEN 1 ELSE 0 END) +
                        (CASE WHEN habit_id IS NOT NULL THEN 1 ELSE 0 END) +
                        (CASE WHEN reward_id IS NOT NULL THEN 1 ELSE 0 END) = 1
                    )
                );

                INSERT INTO trades_v3 (
                    id, owner_id, task_id, habit_id, reward_id, amount, created_at, updated_at, deleted_at
                )
                SELECT
                    id, owner_id, task_id, habit_id, reward_id, amount, created_at, updated_at, deleted_at
                FROM trades;

                DROP TABLE trades;
                ALTER TABLE trades_v3 RENAME TO trades;

                CREATE INDEX IF NOT EXISTS idx_trades_owner_created
                ON trades(owner_id, created_at, id);
                CREATE INDEX IF NOT EXISTS idx_trades_owner_updated
                ON trades(owner_id, updated_at);
                CREATE INDEX IF NOT EXISTS idx_trades_owner_deleted
                ON trades(owner_id, deleted_at);
            """)
        }

        // This shipped as `v4_benefit_commitment`, so keep the identifier stable
        // for already-migrated devices while registering it near its real place
        // in history for fresh installs.
        migrator.registerMigration("v4_benefit_commitment") { db in
            try db.execute(sql: """
                ALTER TABLE habits RENAME COLUMN skip_consequence TO benefit;
                ALTER TABLE tasks RENAME COLUMN skip_consequence TO commitment;
            """)
        }

        migrator.registerMigration("v4_reminders") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS reminders (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    task_id TEXT,
                    habit_id TEXT,
                    scheduled_at REAL NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    CHECK (
                        (CASE WHEN task_id IS NOT NULL THEN 1 ELSE 0 END) +
                        (CASE WHEN habit_id IS NOT NULL THEN 1 ELSE 0 END) = 1
                    )
                );

                CREATE INDEX IF NOT EXISTS idx_reminders_owner_scheduled
                ON reminders(owner_id, scheduled_at, id);
                CREATE INDEX IF NOT EXISTS idx_reminders_owner_updated
                ON reminders(owner_id, updated_at);
            """)
        }

        migrator.registerMigration("v5_reminder_urgency") { db in
            try db.execute(sql: """
                ALTER TABLE reminders ADD COLUMN is_urgent INTEGER NOT NULL DEFAULT 0;
            """)
        }

        migrator.registerMigration("v6_reminder_recurrence") { db in
            try db.execute(sql: """
                ALTER TABLE reminders ADD COLUMN repeat_value INTEGER;
            """)
            try db.execute(sql: """
                ALTER TABLE reminders ADD COLUMN repeat_unit TEXT;
            """)
        }

        migrator.registerMigration("v7_task_dependencies") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS task_task_dependencies (
                    owner_id TEXT NOT NULL,
                    task_id TEXT NOT NULL,
                    depends_on_task_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    PRIMARY KEY(owner_id, task_id, depends_on_task_id)
                );

                CREATE INDEX IF NOT EXISTS idx_task_task_dependencies_owner_updated
                ON task_task_dependencies(owner_id, updated_at);

                CREATE TABLE IF NOT EXISTS task_habit_dependencies (
                    owner_id TEXT NOT NULL,
                    task_id TEXT NOT NULL,
                    habit_id TEXT NOT NULL,
                    required_completions INTEGER NOT NULL,
                    baseline_completion_count INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    PRIMARY KEY(owner_id, task_id, habit_id)
                );

                CREATE INDEX IF NOT EXISTS idx_task_habit_dependencies_owner_updated
                ON task_habit_dependencies(owner_id, updated_at);
                """)
        }

        migrator.registerMigration("v8_trade_refunds") { db in
            try db.execute(sql: """
                ALTER TABLE trades ADD COLUMN refunded_at REAL;
            """)
        }

        migrator.registerMigration("v9_trade_source_name") { db in
            try db.execute(sql: """
                ALTER TABLE trades ADD COLUMN source_name TEXT;
            """)
        }

        migrator.registerMigration("v10_refund_trades") { db in
            try db.execute(sql: """
                CREATE TABLE trades_v10 (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    task_id TEXT,
                    habit_id TEXT,
                    reward_id TEXT,
                    source_name TEXT,
                    amount INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    refunds_trade_id TEXT,
                    CHECK (
                        (CASE WHEN task_id IS NOT NULL THEN 1 ELSE 0 END) +
                        (CASE WHEN habit_id IS NOT NULL THEN 1 ELSE 0 END) +
                        (CASE WHEN reward_id IS NOT NULL THEN 1 ELSE 0 END) = 1
                    )
                );

                INSERT INTO trades_v10 (
                    id, owner_id, task_id, habit_id, reward_id, source_name, amount, created_at, updated_at, deleted_at, refunds_trade_id
                )
                SELECT
                    id, owner_id, task_id, habit_id, reward_id, source_name, amount, created_at, updated_at, deleted_at, NULL
                FROM trades;

                INSERT INTO trades_v10 (
                    id, owner_id, task_id, habit_id, reward_id, source_name, amount, created_at, updated_at, deleted_at, refunds_trade_id
                )
                SELECT
                    lower(
                        hex(randomblob(4)) || '-' ||
                        hex(randomblob(2)) || '-' ||
                        hex(randomblob(2)) || '-' ||
                        hex(randomblob(2)) || '-' ||
                        hex(randomblob(6))
                    ),
                    owner_id,
                    task_id,
                    habit_id,
                    reward_id,
                    source_name,
                    -amount,
                    refunded_at,
                    refunded_at,
                    deleted_at,
                    id
                FROM trades
                WHERE refunded_at IS NOT NULL;

                DROP TABLE trades;
                ALTER TABLE trades_v10 RENAME TO trades;

                CREATE INDEX IF NOT EXISTS idx_trades_owner_created
                ON trades(owner_id, created_at, id);
                CREATE INDEX IF NOT EXISTS idx_trades_owner_updated
                ON trades(owner_id, updated_at);
                CREATE INDEX IF NOT EXISTS idx_trades_owner_deleted
                ON trades(owner_id, deleted_at);
                CREATE INDEX IF NOT EXISTS idx_trades_refunds_trade_id
                ON trades(refunds_trade_id);
            """)
        }

        migrator.registerMigration("v11_repair_refund_trade_migration_state") { db in
            try db.execute(sql: """
                CREATE TEMP TABLE refund_trade_id_repairs (
                    old_id TEXT PRIMARY KEY,
                    new_id TEXT NOT NULL
                );

                INSERT INTO refund_trade_id_repairs (old_id, new_id)
                SELECT
                    id,
                    lower(
                        hex(randomblob(4)) || '-' ||
                        hex(randomblob(2)) || '-' ||
                        hex(randomblob(2)) || '-' ||
                        hex(randomblob(2)) || '-' ||
                        hex(randomblob(6))
                    )
                FROM trades
                WHERE refunds_trade_id IS NOT NULL
                  AND (
                    length(id) != 36
                    OR substr(id, 9, 1) != '-'
                    OR substr(id, 14, 1) != '-'
                    OR substr(id, 19, 1) != '-'
                    OR substr(id, 24, 1) != '-'
                  );

                UPDATE dirty_records
                SET record_id = (
                    SELECT new_id
                    FROM refund_trade_id_repairs
                    WHERE old_id = dirty_records.record_id
                )
                WHERE entity_kind = 'trades'
                  AND record_id IN (SELECT old_id FROM refund_trade_id_repairs);

                UPDATE trades
                SET id = (
                    SELECT new_id
                    FROM refund_trade_id_repairs
                    WHERE old_id = trades.id
                )
                WHERE id IN (SELECT old_id FROM refund_trade_id_repairs);

                UPDATE trades AS refund
                SET deleted_at = (
                    SELECT original.deleted_at
                    FROM trades AS original
                    WHERE original.id = refund.refunds_trade_id
                )
                WHERE refund.refunds_trade_id IS NOT NULL
                  AND refund.deleted_at IS NULL
                  AND EXISTS (
                    SELECT 1
                    FROM trades AS original
                    WHERE original.id = refund.refunds_trade_id
                      AND original.deleted_at IS NOT NULL
                  );

                DROP TABLE refund_trade_id_repairs;
            """)
        }

        migrator.registerMigration("v12_special_offers") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS special_offers (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    entity_kind TEXT NOT NULL,
                    entity_id TEXT NOT NULL,
                    modifier_percent INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    expires_at REAL NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_special_offers_owner_updated
                ON special_offers(owner_id, updated_at);

                CREATE INDEX IF NOT EXISTS idx_special_offers_owner_entity
                ON special_offers(owner_id, entity_kind, entity_id);
            """)
        }

        migrator.registerMigration("v13_special_offer_active_entity_uniqueness") { db in
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS idx_special_offers_owner_active_entity
                ON special_offers(owner_id, entity_kind, entity_id)
                WHERE deleted_at IS NULL;
            """)
        }

        migrator.registerMigration("v14_reward_lockout") { db in
            try db.execute(sql: """
                ALTER TABLE rewards ADD COLUMN lockout_duration_seconds INTEGER;
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

    static func double(_ row: Row, index: Int) -> Double {
        row[index]
    }

    static func optionalDouble(_ row: Row, index: Int) -> Double? {
        row[index]
    }

    static func date(_ row: Row, index: Int) -> Date {
        Date(timeIntervalSince1970: double(row, index: index))
    }

    static func optionalDate(_ row: Row, index: Int) -> Date? {
        guard let value: Double = row[index] else { return nil }
        return Date(timeIntervalSince1970: value)
    }
}
