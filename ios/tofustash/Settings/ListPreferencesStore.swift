import Foundation

@Observable
@MainActor
final class ListPreferencesStore {
    enum ListScope: String {
        case habits
        case rewards
    }

    private let databaseURL: URL
    private let database = AppDatabase.shared

    private(set) var currentOwnerID: String
    private(set) var habitPreferences: EntityListPreferences
    private(set) var rewardPreferences: EntityListPreferences

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = StorageOwner.local
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        self.habitPreferences = Self.loadPreferences(scope: .habits, ownerID: initialOwnerID, database: database, url: databaseURL)
        self.rewardPreferences = Self.loadPreferences(scope: .rewards, ownerID: initialOwnerID, database: database, url: databaseURL)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        habitPreferences = Self.loadPreferences(scope: .habits, ownerID: ownerID, database: database, url: databaseURL)
        rewardPreferences = Self.loadPreferences(scope: .rewards, ownerID: ownerID, database: database, url: databaseURL)
    }

    func migratePreferences(from sourceOwnerID: String, to destinationOwnerID: String) -> Bool {
        guard sourceOwnerID != destinationOwnerID else { return false }
        do {
            let migrated = try database.transaction(at: databaseURL) { db in
                try self.migratePreferences(from: sourceOwnerID, to: destinationOwnerID, on: db)
            }
            if migrated {
                setCurrentOwner(currentOwnerID)
            }
            return migrated
        } catch {
            assertionFailure("Failed to migrate list preferences: \(error)")
            return false
        }
    }

    func setHabitSort(_ sort: EntityListSortOption) {
        mutatePreferences(for: .habits) { $0.sort = sort }
    }

    func setRewardSort(_ sort: EntityListSortOption) {
        mutatePreferences(for: .rewards) { $0.sort = sort }
    }

    func toggleHabitTag(_ tagID: RecordID) {
        mutatePreferences(for: .habits) { preferences in
            toggleTag(tagID, in: &preferences)
        }
    }

    func toggleRewardTag(_ tagID: RecordID) {
        mutatePreferences(for: .rewards) { preferences in
            toggleTag(tagID, in: &preferences)
        }
    }

    func clearHabitFilters() {
        clearFilters(for: .habits)
    }

    func clearRewardFilters() {
        clearFilters(for: .rewards)
    }

    @discardableResult
    func sanitizeHabitSelectedTags(validTagIDs: Set<RecordID>) -> Bool {
        sanitizeSelectedTags(for: .habits, validTagIDs: validTagIDs)
    }

    @discardableResult
    func sanitizeRewardSelectedTags(validTagIDs: Set<RecordID>) -> Bool {
        sanitizeSelectedTags(for: .rewards, validTagIDs: validTagIDs)
    }

    @discardableResult
    func sanitizeSelectedTags(
        validHabitTagIDs: Set<RecordID>,
        validRewardTagIDs: Set<RecordID>
    ) -> Bool {
        let habitsChanged = sanitizeHabitSelectedTags(validTagIDs: validHabitTagIDs)
        let rewardsChanged = sanitizeRewardSelectedTags(validTagIDs: validRewardTagIDs)
        return habitsChanged || rewardsChanged
    }

    private func toggleTag(_ tagID: RecordID, in preferences: inout EntityListPreferences) {
        if let index = preferences.selectedTagIDs.firstIndex(of: tagID) {
            preferences.selectedTagIDs.remove(at: index)
        } else {
            preferences.selectedTagIDs.append(tagID)
            preferences.selectedTagIDs.sort { $0.rawValue < $1.rawValue }
        }
    }

    private func clearFilters(for scope: ListScope) {
        mutatePreferences(for: scope) { preferences in
            preferences.selectedTagIDs = []
        }
    }

    @discardableResult
    private func sanitizeSelectedTags(for scope: ListScope, validTagIDs: Set<RecordID>) -> Bool {
        var didChange = false
        mutatePreferences(for: scope) { preferences in
            let sanitized = preferences.selectedTagIDs.filter { validTagIDs.contains($0) }
            if sanitized != preferences.selectedTagIDs {
                preferences.selectedTagIDs = sanitized
                didChange = true
            }
        }
        return didChange
    }

    private func mutatePreferences(for scope: ListScope, _ mutate: (inout EntityListPreferences) -> Void) {
        let current = preferences(for: scope)
        var next = current
        mutate(&next)
        guard next != current else { return }
        do {
            try database.transaction(at: databaseURL) { db in
                try self.savePreferences(next, scope: scope, ownerID: self.currentOwnerID, on: db)
            }
        } catch {
            assertionFailure("Failed to save list preferences: \(error)")
            return
        }
        setPreferences(next, for: scope)
    }

    private func preferences(for scope: ListScope) -> EntityListPreferences {
        switch scope {
        case .habits:
            habitPreferences
        case .rewards:
            rewardPreferences
        }
    }

    private func setPreferences(_ preferences: EntityListPreferences, for scope: ListScope) {
        switch scope {
        case .habits:
            habitPreferences = preferences
        case .rewards:
            rewardPreferences = preferences
        }
    }

    private func preferenceRowExists(scope: ListScope, ownerID: String) -> Bool {
        do {
            return try database.queryOne(
                "SELECT 1 FROM list_preferences WHERE owner_id = ? AND scope = ? LIMIT 1",
                bindings: [.text(ownerID), .text(scope.rawValue)],
                at: databaseURL
            ) { _ in
                true
            } ?? false
        } catch {
            assertionFailure("Failed to check list preference row: \(error)")
            return false
        }
    }

    private func preferenceRowExists(
        scope: ListScope,
        ownerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> Bool {
        try database.queryOne(
            "SELECT 1 FROM list_preferences WHERE owner_id = ? AND scope = ? LIMIT 1",
            bindings: [.text(ownerID), .text(scope.rawValue)],
            on: databaseHandle
        ) { _ in
            true
        } ?? false
    }

    private func savePreferences(
        _ preferences: EntityListPreferences,
        scope: ListScope,
        ownerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws {
        let selectedTagIDs = (try? String(data: JSONEncoder().encode(preferences.selectedTagIDs), encoding: .utf8)) ?? "[]"
        try database.execute(
            """
            INSERT INTO list_preferences (owner_id, scope, sort, selected_tag_ids_json)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(owner_id, scope) DO UPDATE SET
                sort = excluded.sort,
                selected_tag_ids_json = excluded.selected_tag_ids_json
            """,
            bindings: [
                .text(ownerID),
                .text(scope.rawValue),
                .text(preferences.sort.rawValue),
                .text(selectedTagIDs)
            ],
            on: databaseHandle
        )
    }

    func migratePreferences(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> Bool {
        guard sourceOwnerID != destinationOwnerID else { return false }

        let sourceHabit = try Self.loadPreferences(
            scope: .habits,
            ownerID: sourceOwnerID,
            database: database,
            on: databaseHandle
        ) ?? EntityListPreferences()
        let sourceReward = try Self.loadPreferences(
            scope: .rewards,
            ownerID: sourceOwnerID,
            database: database,
            on: databaseHandle
        ) ?? EntityListPreferences()

        var migrated = false
        if try preferenceRowExists(scope: .habits, ownerID: sourceOwnerID, on: databaseHandle) {
            try savePreferences(sourceHabit, scope: .habits, ownerID: destinationOwnerID, on: databaseHandle)
            try database.execute(
                "DELETE FROM list_preferences WHERE owner_id = ? AND scope = ?",
                bindings: [.text(sourceOwnerID), .text(ListScope.habits.rawValue)],
                on: databaseHandle
            )
            migrated = true
        }

        if try preferenceRowExists(scope: .rewards, ownerID: sourceOwnerID, on: databaseHandle) {
            try savePreferences(sourceReward, scope: .rewards, ownerID: destinationOwnerID, on: databaseHandle)
            try database.execute(
                "DELETE FROM list_preferences WHERE owner_id = ? AND scope = ?",
                bindings: [.text(sourceOwnerID), .text(ListScope.rewards.rawValue)],
                on: databaseHandle
            )
            migrated = true
        }

        return migrated
    }

    private static func loadPreferences(
        scope: ListScope,
        ownerID: String,
        database: AppDatabase,
        url: URL
    ) -> EntityListPreferences {
        do {
            return try database.queryOne(
                """
                SELECT sort, selected_tag_ids_json
                FROM list_preferences
                WHERE owner_id = ? AND scope = ?
                """,
                bindings: [.text(ownerID), .text(scope.rawValue)],
                at: url
            ) { row in
                let sort = EntityListSortOption(rawValue: SQLiteColumn.text(row, index: 0)) ?? .priceHighToLow
                let rawJSON = SQLiteColumn.text(row, index: 1)
                let selectedTagIDs = (try? JSONDecoder().decode([RecordID].self, from: Data(rawJSON.utf8))) ?? []
                return EntityListPreferences(sort: sort, selectedTagIDs: selectedTagIDs)
            } ?? EntityListPreferences()
        } catch {
            assertionFailure("Failed to load list preferences: \(error)")
            return EntityListPreferences()
        }
    }

    private static func loadPreferences(
        scope: ListScope,
        ownerID: String,
        database: AppDatabase,
        on databaseHandle: AppDatabaseHandle
    ) throws -> EntityListPreferences? {
        try database.queryOne(
            """
            SELECT sort, selected_tag_ids_json
            FROM list_preferences
            WHERE owner_id = ? AND scope = ?
            """,
            bindings: [.text(ownerID), .text(scope.rawValue)],
            on: databaseHandle
        ) { row in
            let sort = EntityListSortOption(rawValue: SQLiteColumn.text(row, index: 0)) ?? .priceHighToLow
            let rawJSON = SQLiteColumn.text(row, index: 1)
            let selectedTagIDs = (try? JSONDecoder().decode([RecordID].self, from: Data(rawJSON.utf8))) ?? []
            return EntityListPreferences(sort: sort, selectedTagIDs: selectedTagIDs)
        }
    }
}
