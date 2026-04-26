import Foundation

@Observable
@MainActor
final class UserSettingsStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared

    private(set) var currentOwnerID: String
    private(set) var generalDifficulty: Double = 5.0

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        self.generalDifficulty = loadDifficulty(ownerID: initialOwnerID) ?? 5.0
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        generalDifficulty = loadDifficulty(ownerID: ownerID) ?? 5.0
    }

    func migrateSettings(from sourceOwnerID: String, to destinationOwnerID: String) -> Bool {
        guard sourceOwnerID != destinationOwnerID else { return false }
        guard let sourceDifficulty = loadDifficulty(ownerID: sourceOwnerID) else { return false }

        do {
            try database.transaction(at: databaseURL) { db in
                try self.upsertDifficulty(sourceDifficulty, ownerID: destinationOwnerID, on: db)
                try self.database.execute(
                    "DELETE FROM user_settings WHERE owner_id = ?",
                    bindings: [.text(sourceOwnerID)],
                    on: db
                )
            }
        } catch {
            assertionFailure("Failed to migrate user settings: \(error)")
            return false
        }

        generalDifficulty = loadDifficulty(ownerID: currentOwnerID) ?? 5.0
        return true
    }

    func setGeneralDifficulty(_ value: Double, shouldNotifySync: Bool = true) {
        guard value > 0, value < 1000 else { return }
        do {
            try database.execute(
                """
                INSERT INTO user_settings (owner_id, general_difficulty)
                VALUES (?, ?)
                ON CONFLICT(owner_id) DO UPDATE SET
                    general_difficulty = excluded.general_difficulty
                """,
                bindings: [.text(currentOwnerID), .double(value)],
                at: databaseURL
            )
        } catch {
            assertionFailure("Failed to set general difficulty: \(error)")
        }

        generalDifficulty = value

        if shouldNotifySync {
            SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .generalDifficulty, recordIDs: []))
        }
    }

    private func loadDifficulty(ownerID: String) -> Double? {
        do {
            return try database.queryOne(
                "SELECT general_difficulty FROM user_settings WHERE owner_id = ?",
                bindings: [.text(ownerID)],
                at: databaseURL
            ) { row in
                SQLiteColumn.double(row, index: 0)
            }
        } catch {
            assertionFailure("Failed to load general difficulty: \(error)")
            return nil
        }
    }

    private func upsertDifficulty(_ value: Double, ownerID: String, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO user_settings (owner_id, general_difficulty)
            VALUES (?, ?)
            ON CONFLICT(owner_id) DO UPDATE SET
                general_difficulty = excluded.general_difficulty
            """,
            bindings: [.text(ownerID), .double(value)],
            on: databaseHandle
        )
    }
}
