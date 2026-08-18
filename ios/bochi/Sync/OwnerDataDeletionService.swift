import Foundation

struct AccountDeletionCleanupResult: Equatable, Sendable {
    let reminderIDs: [RecordID]
}

@MainActor
struct OwnerDataDeletionService {
    private let databaseURL: URL
    private let database = AppDatabase.shared

    init(storageURL: URL? = nil) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        _ = try? database.connection(at: databaseURL)
    }

    func deleteAccountData(userID: String) throws -> AccountDeletionCleanupResult {
        try database.transaction(at: databaseURL) { db in
            let reminderIDs = try database.query(
                """
                SELECT id
                FROM reminders
                WHERE owner_id = ?
                ORDER BY id ASC
                """,
                bindings: [.text(userID)],
                on: db
            ) { row in
                RecordID(SQLiteColumn.text(row, index: 0))
            }

            for tableName in ownerScopedTableNames {
                try database.execute(
                    "DELETE FROM \(tableName) WHERE owner_id = ?",
                    bindings: [.text(userID)],
                    on: db
                )
            }

            for tableName in syncTableNames {
                try database.execute(
                    "DELETE FROM \(tableName) WHERE user_id = ?",
                    bindings: [.text(userID)],
                    on: db
                )
            }

            return AccountDeletionCleanupResult(reminderIDs: reminderIDs)
        }
    }

    private var ownerScopedTableNames: [String] {
        [
            "timers",
            "tasks",
            "rewards",
            "tags",
            "trades",
            "task_tags",
            "recurring_task_tags",
            "reward_tags",
            "task_task_dependencies",
            "task_recurring_task_dependencies",
            "reward_task_dependencies",
            "reward_recurring_task_dependencies",
            "reminders",
            "user_settings",
            "list_preferences",
            "balance_projections"
        ]
    }

    private var syncTableNames: [String] {
        [
            "sync_state",
            "dirty_records",
            "dirty_flags"
        ]
    }
}
