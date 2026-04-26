import Foundation

@Observable
@MainActor
final class UserSettingsStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore

    private(set) var currentOwnerID: String
    private(set) var generalDifficulty: Double = 5.0

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.syncStateStore = SyncStateStore(storageURL: self.databaseURL)
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
        do {
            let migrated = try database.transaction(at: databaseURL) { db in
                try self.migrateSettings(from: sourceOwnerID, to: destinationOwnerID, on: db)
            }
            if migrated {
                generalDifficulty = loadDifficulty(ownerID: currentOwnerID) ?? 5.0
            }
            return migrated
        } catch {
            assertionFailure("Failed to migrate user settings: \(error)")
            return false
        }
    }

    func setGeneralDifficulty(_ value: Double, shouldNotifySync: Bool = true) {
        guard value > 0, value < 1000 else { return }
        do {
            try database.transaction(at: databaseURL) { db in
                try self.upsertDifficulty(value, ownerID: self.currentOwnerID, on: db)
                if shouldNotifySync, self.currentOwnerID != StorageOwner.local {
                    try self.syncStateStore.markDirty(userID: self.currentOwnerID, kind: .generalDifficulty, ids: [], on: db)
                }
            }
        } catch {
            assertionFailure("Failed to set general difficulty: \(error)")
            return
        }

        generalDifficulty = value

        if shouldNotifySync {
            SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .generalDifficulty, recordIDs: []))
        }
    }

    func migrateSettings(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> Bool {
        guard sourceOwnerID != destinationOwnerID else { return false }
        guard let sourceDifficulty = try loadDifficulty(ownerID: sourceOwnerID, on: databaseHandle) else { return false }

        try upsertDifficulty(sourceDifficulty, ownerID: destinationOwnerID, on: databaseHandle)
        try database.execute(
            "DELETE FROM user_settings WHERE owner_id = ?",
            bindings: [.text(sourceOwnerID)],
            on: databaseHandle
        )
        return true
    }

    func persistGeneralDifficulty(_ value: Double) throws {
        try database.transaction(at: databaseURL) { db in
            try self.upsertDifficulty(value, ownerID: self.currentOwnerID, on: db)
        }
        generalDifficulty = value
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

    private func loadDifficulty(ownerID: String, on databaseHandle: AppDatabaseHandle) throws -> Double? {
        try database.queryOne(
            "SELECT general_difficulty FROM user_settings WHERE owner_id = ?",
            bindings: [.text(ownerID)],
            on: databaseHandle
        ) { row in
            SQLiteColumn.double(row, index: 0)
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
