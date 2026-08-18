import Foundation

// Sync flow: theme palette changes use a dirty generation so local edits made
// during a sync can survive later pull/push responses.
@Observable
@MainActor
final class UserSettingsStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared
    private let syncStateStore: SyncStateStore
    private let userDefaults: UserDefaults
    private let showsEntityRowDetailsKey = "bochi.settings.entityRows.showDetails"

    private(set) var currentOwnerID: String
    private(set) var themePalettes: BochiThemePalettePreferences = .default
    private(set) var showsEntityRowDetails = true

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device",
        userDefaults: UserDefaults? = nil
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.syncStateStore = SyncStateStore(storageURL: self.databaseURL)
        self.userDefaults = userDefaults ?? .standard
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        self.themePalettes = loadThemePalettes(ownerID: initialOwnerID) ?? .default
        self.showsEntityRowDetails = self.userDefaults.object(forKey: showsEntityRowDetailsKey) == nil
            ? true
            : self.userDefaults.bool(forKey: showsEntityRowDetailsKey)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        themePalettes = loadThemePalettes(ownerID: ownerID) ?? .default
    }

    func migrateSettings(from sourceOwnerID: String, to destinationOwnerID: String) -> Bool {
        guard sourceOwnerID != destinationOwnerID else { return false }
        do {
            let migrated = try database.transaction(at: databaseURL) { db in
                try self.migrateSettings(from: sourceOwnerID, to: destinationOwnerID, on: db)
            }
            if migrated {
                themePalettes = loadThemePalettes(ownerID: currentOwnerID) ?? .default
            }
            return migrated
        } catch {
            assertionFailure("Failed to migrate user settings: \(error)")
            return false
        }
    }

    func setThemePalettes(_ palettes: BochiThemePalettePreferences, shouldNotifySync: Bool = true) {
        do {
            try database.transaction(at: databaseURL) { db in
                try self.upsertThemePalettes(palettes, ownerID: self.currentOwnerID, on: db)
                if shouldNotifySync, self.currentOwnerID != StorageOwner.local {
                    try self.syncStateStore.markDirty(userID: self.currentOwnerID, kind: .themePalettes, ids: [], on: db)
                }
            }
        } catch {
            assertionFailure("Failed to set theme palettes: \(error)")
            return
        }

        themePalettes = palettes

        if shouldNotifySync {
            SyncMutationCenter.post(SyncMutation(ownerID: currentOwnerID, entityKind: .themePalettes, recordIDs: []))
        }
    }

    func effectiveThemePalettes(hasPremiumAccess: Bool) -> BochiThemePalettePreferences {
        hasPremiumAccess ? themePalettes : .default
    }

    func setShowsEntityRowDetails(_ showsDetails: Bool) {
        showsEntityRowDetails = showsDetails
        userDefaults.set(showsDetails, forKey: showsEntityRowDetailsKey)
    }

    func migrateSettings(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> Bool {
        guard sourceOwnerID != destinationOwnerID else { return false }
        guard let sourceSettings = try loadSettings(ownerID: sourceOwnerID, on: databaseHandle) else { return false }

        try upsertSettings(sourceSettings, ownerID: destinationOwnerID, on: databaseHandle)
        try database.execute(
            "DELETE FROM user_settings WHERE owner_id = ?",
            bindings: [.text(sourceOwnerID)],
            on: databaseHandle
        )
        return true
    }

    func persistThemePalettes(_ palettes: BochiThemePalettePreferences) throws {
        try database.transaction(at: databaseURL) { db in
            try self.upsertThemePalettes(palettes, ownerID: self.currentOwnerID, on: db)
        }
        themePalettes = palettes
    }

    private func loadThemePalettes(ownerID: String) -> BochiThemePalettePreferences? {
        do {
            return try database.transaction(at: databaseURL) { db in
                try self.loadSettings(ownerID: ownerID, on: db)?.themePalettes
            }
        } catch {
            assertionFailure("Failed to load theme palettes: \(error)")
            return nil
        }
    }

    private struct StoredSettings {
        let themePalettes: BochiThemePalettePreferences
    }

    private func loadSettings(ownerID: String, on databaseHandle: AppDatabaseHandle) throws -> StoredSettings? {
        try database.queryOne(
            """
            SELECT
                theme_palette_main,
                theme_palette_accent
            FROM user_settings
            WHERE owner_id = ?
            """,
            bindings: [.text(ownerID)],
            on: databaseHandle
        ) { row in
            let defaults = BochiThemePalettePreferences.default
            return StoredSettings(
                themePalettes: BochiThemePalettePreferences(
                    main: BochiThemePaletteName(rawValue: SQLiteColumn.text(row, index: 0)) ?? defaults.main,
                    accent: BochiThemeAccentChoice(rawValue: SQLiteColumn.text(row, index: 1)) ?? defaults.accent
                )
            )
        }
    }

    private func upsertThemePalettes(
        _ palettes: BochiThemePalettePreferences,
        ownerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try upsertSettings(
            StoredSettings(themePalettes: palettes),
            ownerID: ownerID,
            on: databaseHandle
        )
    }

    private func upsertSettings(_ settings: StoredSettings, ownerID: String, on databaseHandle: AppDatabaseHandle) throws {
        try database.execute(
            """
            INSERT INTO user_settings (
                owner_id,
                theme_palette_main,
                theme_palette_accent
            )
            VALUES (?, ?, ?)
            ON CONFLICT(owner_id) DO UPDATE SET
                theme_palette_main = excluded.theme_palette_main,
                theme_palette_accent = excluded.theme_palette_accent
            """,
            bindings: [
                .text(ownerID),
                .text(settings.themePalettes.main.rawValue),
                .text(settings.themePalettes.accent.rawValue)
            ],
            on: databaseHandle
        )
    }
}
