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

    private var queuesByPath: [String: DatabaseQueue] = [:]

    func connection(at url: URL) throws -> DatabaseQueue {
        if let existing = queuesByPath[url.path] {
            return existing
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        do {
            let queue = try DatabaseQueue(path: url.path)
            try queue.write { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
                try db.execute(sql: "PRAGMA journal_mode = WAL")
            }
            try migrate(queue)
            queuesByPath[url.path] = queue
            return queue
        } catch {
            throw AppDatabaseError.openFailed(String(describing: error))
        }
    }

    func transaction(at url: URL, _ body: (AppDatabaseHandle) throws -> Void) throws {
        let queue = try connection(at: url)
        do {
            try queue.write { db in
                try db.inTransaction {
                    try body(db)
                    return .commit
                }
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
        let queue = try connection(at: url)
        try queue.write { db in
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
        let queue = try connection(at: url)
        return try queue.read { db in
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
        let queue = try connection(at: url)
        return try queue.read { db in
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

    private func migrate(_ queue: DatabaseQueue) throws {
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

        try migrator.migrate(queue)
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
