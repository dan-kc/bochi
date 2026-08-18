import Foundation

@Observable
@MainActor
final class ListPreferencesStore {
    enum ListScope: String, CaseIterable {
        case earn
        case tasks
        case recurringTasks
        case rewards
    }

    private let databaseURL: URL
    private let database = AppDatabase.shared

    private(set) var currentOwnerID: String
    private(set) var earnPreferences: EntityListPreferences
    private(set) var taskPreferences: EntityListPreferences
    private(set) var recurringTaskPreferences: EntityListPreferences
    private(set) var rewardPreferences: EntityListPreferences

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = StorageOwner.local
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        self.earnPreferences = Self.loadPreferences(scope: .earn, ownerID: initialOwnerID, database: database, url: databaseURL)
        self.taskPreferences = Self.loadPreferences(scope: .tasks, ownerID: initialOwnerID, database: database, url: databaseURL)
        self.recurringTaskPreferences = Self.loadPreferences(scope: .recurringTasks, ownerID: initialOwnerID, database: database, url: databaseURL)
        self.rewardPreferences = Self.loadPreferences(scope: .rewards, ownerID: initialOwnerID, database: database, url: databaseURL)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        earnPreferences = Self.loadPreferences(scope: .earn, ownerID: ownerID, database: database, url: databaseURL)
        taskPreferences = Self.loadPreferences(scope: .tasks, ownerID: ownerID, database: database, url: databaseURL)
        recurringTaskPreferences = Self.loadPreferences(scope: .recurringTasks, ownerID: ownerID, database: database, url: databaseURL)
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

    func setRecurringTaskSort(_ sort: EntityListSortOption) {
        mutatePreferences(for: .recurringTasks) { $0.sort = sort }
    }

    func setEarnSort(_ sort: EntityListSortOption) {
        mutatePreferences(for: .earn) { $0.sort = sort }
    }

    func setTaskSort(_ sort: EntityListSortOption) {
        mutatePreferences(for: .tasks) { $0.sort = sort }
    }

    func setRewardSort(_ sort: EntityListSortOption) {
        mutatePreferences(for: .rewards) { $0.sort = sort }
    }

    func toggleTaskTag(_ tagID: RecordID) {
        mutatePreferences(for: .tasks) { preferences in
            toggleHiddenTag(tagID, in: &preferences)
        }
    }

    func toggleEarnTag(_ tagID: RecordID) {
        mutatePreferences(for: .earn) { preferences in
            toggleHiddenTag(tagID, in: &preferences)
        }
    }

    func toggleRecurringTaskTag(_ tagID: RecordID) {
        mutatePreferences(for: .recurringTasks) { preferences in
            toggleHiddenTag(tagID, in: &preferences)
        }
    }

    func toggleRewardTag(_ tagID: RecordID) {
        mutatePreferences(for: .rewards) { preferences in
            toggleHiddenTag(tagID, in: &preferences)
        }
    }

    func toggleTaskStatus(_ status: EntityListStatusFilter) {
        mutatePreferences(for: .tasks) { preferences in
            toggleHiddenStatus(status, in: &preferences)
        }
    }

    func toggleEarnStatus(_ status: EntityListStatusFilter) {
        mutatePreferences(for: .earn) { preferences in
            EarnListFilterSupport.toggleHiddenStatus(status, in: &preferences)
        }
    }

    func toggleEarnTaskGroup() {
        mutatePreferences(for: .earn) { preferences in
            EarnListFilterSupport.toggleTaskGroup(in: &preferences)
        }
    }

    func toggleEarnTaskCompletion(_ status: EntityListStatusFilter) {
        mutatePreferences(for: .earn) { preferences in
            EarnListFilterSupport.toggleTaskCompletion(status, in: &preferences)
        }
    }

    func toggleRecurringTaskStatus(_ status: EntityListStatusFilter) {
        mutatePreferences(for: .recurringTasks) { preferences in
            toggleHiddenStatus(status, in: &preferences)
        }
    }

    func toggleRewardStatus(_ status: EntityListStatusFilter) {
        mutatePreferences(for: .rewards) { preferences in
            toggleHiddenStatus(status, in: &preferences)
        }
    }

    func clearRecurringTaskFilters() {
        clearFilters(for: .recurringTasks)
    }

    func clearEarnFilters() {
        clearFilters(for: .earn)
    }

    func clearTaskFilters() {
        clearFilters(for: .tasks)
    }

    func clearRewardFilters() {
        clearFilters(for: .rewards)
    }

    @discardableResult
    func sanitizeTaskSelectedTags(validTagIDs: Set<RecordID>) -> Bool {
        sanitizeSelectedTags(for: .tasks, validTagIDs: validTagIDs)
    }

    @discardableResult
    func sanitizeEarnSelectedTags(validTagIDs: Set<RecordID>) -> Bool {
        sanitizeSelectedTags(for: .earn, validTagIDs: validTagIDs)
    }

    @discardableResult
    func sanitizeRecurringTaskSelectedTags(validTagIDs: Set<RecordID>) -> Bool {
        sanitizeSelectedTags(for: .recurringTasks, validTagIDs: validTagIDs)
    }

    @discardableResult
    func sanitizeRewardSelectedTags(validTagIDs: Set<RecordID>) -> Bool {
        sanitizeSelectedTags(for: .rewards, validTagIDs: validTagIDs)
    }

    @discardableResult
    func sanitizeSelectedTags(
        validTaskTagIDs: Set<RecordID>,
        validRecurringTaskTagIDs: Set<RecordID>,
        validRewardTagIDs: Set<RecordID>
    ) -> Bool {
        let earnChanged = sanitizeEarnSelectedTags(validTagIDs: validTaskTagIDs.union(validRecurringTaskTagIDs))
        let tasksChanged = sanitizeTaskSelectedTags(validTagIDs: validTaskTagIDs)
        let recurringTasksChanged = sanitizeRecurringTaskSelectedTags(validTagIDs: validRecurringTaskTagIDs)
        let rewardsChanged = sanitizeRewardSelectedTags(validTagIDs: validRewardTagIDs)
        return earnChanged || tasksChanged || recurringTasksChanged || rewardsChanged
    }

    private func toggleHiddenStatus(_ status: EntityListStatusFilter, in preferences: inout EntityListPreferences) {
        if let index = preferences.hiddenStatusFilters.firstIndex(of: status) {
            preferences.hiddenStatusFilters.remove(at: index)
        } else {
            preferences.hiddenStatusFilters.append(status)
            preferences.hiddenStatusFilters.sort { $0.rawValue < $1.rawValue }
        }
    }

    private func toggleHiddenTag(_ tagID: RecordID, in preferences: inout EntityListPreferences) {
        if let index = preferences.hiddenTagIDs.firstIndex(of: tagID) {
            preferences.hiddenTagIDs.remove(at: index)
        } else {
            preferences.hiddenTagIDs.append(tagID)
            preferences.hiddenTagIDs.sort { $0.rawValue < $1.rawValue }
        }
    }

    private func clearFilters(for scope: ListScope) {
        mutatePreferences(for: scope) { preferences in
            preferences.hiddenStatusFilters = []
            preferences.hiddenTagIDs = []
        }
    }

    @discardableResult
    private func sanitizeSelectedTags(for scope: ListScope, validTagIDs: Set<RecordID>) -> Bool {
        var didChange = false
        mutatePreferences(for: scope) { preferences in
            let sanitized = preferences.hiddenTagIDs.filter { validTagIDs.contains($0) }
            if sanitized != preferences.hiddenTagIDs {
                preferences.hiddenTagIDs = sanitized
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
        case .earn:
            earnPreferences
        case .tasks:
            taskPreferences
        case .recurringTasks:
            recurringTaskPreferences
        case .rewards:
            rewardPreferences
        }
    }

    private func setPreferences(_ preferences: EntityListPreferences, for scope: ListScope) {
        switch scope {
        case .earn:
            earnPreferences = preferences
        case .tasks:
            taskPreferences = preferences
        case .recurringTasks:
            recurringTaskPreferences = preferences
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
        let hiddenStatusFilters = (try? String(data: JSONEncoder().encode(preferences.hiddenStatusFilters), encoding: .utf8)) ?? "[]"
        let hiddenTagIDs = (try? String(data: JSONEncoder().encode(preferences.hiddenTagIDs), encoding: .utf8)) ?? "[]"
        try database.execute(
            """
            INSERT INTO list_preferences (owner_id, scope, sort, selected_tag_ids_json, hidden_status_filters_json, hidden_tag_ids_json)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_id, scope) DO UPDATE SET
                sort = excluded.sort,
                selected_tag_ids_json = excluded.selected_tag_ids_json,
                hidden_status_filters_json = excluded.hidden_status_filters_json,
                hidden_tag_ids_json = excluded.hidden_tag_ids_json
            """,
            bindings: [
                .text(ownerID),
                .text(scope.rawValue),
                .text(preferences.sort.rawValue),
                .text("[]"),
                .text(hiddenStatusFilters),
                .text(hiddenTagIDs)
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

        var migrated = false
        for scope in ListScope.allCases {
            if try migratePreferences(
                scope: scope,
                from: sourceOwnerID,
                to: destinationOwnerID,
                on: databaseHandle
            ) {
                migrated = true
            }
        }

        return migrated
    }

    private func migratePreferences(
        scope: ListScope,
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        on databaseHandle: AppDatabaseHandle
    ) throws -> Bool {
        guard try preferenceRowExists(scope: scope, ownerID: sourceOwnerID, on: databaseHandle) else {
            return false
        }

        let sourcePreferences = try Self.loadPreferences(
            scope: scope,
            ownerID: sourceOwnerID,
            database: database,
            on: databaseHandle
        ) ?? EntityListPreferences()

        try savePreferences(sourcePreferences, scope: scope, ownerID: destinationOwnerID, on: databaseHandle)
        try database.execute(
            "DELETE FROM list_preferences WHERE owner_id = ? AND scope = ?",
            bindings: [.text(sourceOwnerID), .text(scope.rawValue)],
            on: databaseHandle
        )

        return true
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
                SELECT sort, hidden_status_filters_json, hidden_tag_ids_json
                FROM list_preferences
                WHERE owner_id = ? AND scope = ?
                """,
                bindings: [.text(ownerID), .text(scope.rawValue)],
                at: url
            ) { row in
                decodePreferences(
                    sortRawValue: SQLiteColumn.text(row, index: 0),
                    rawStatusJSON: SQLiteColumn.text(row, index: 1),
                    rawHiddenTagJSON: SQLiteColumn.text(row, index: 2)
                )
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
            SELECT sort, hidden_status_filters_json, hidden_tag_ids_json
            FROM list_preferences
            WHERE owner_id = ? AND scope = ?
            """,
            bindings: [.text(ownerID), .text(scope.rawValue)],
            on: databaseHandle
        ) { row in
            decodePreferences(
                sortRawValue: SQLiteColumn.text(row, index: 0),
                rawStatusJSON: SQLiteColumn.text(row, index: 1),
                rawHiddenTagJSON: SQLiteColumn.text(row, index: 2)
            )
        }
    }

    private static func decodePreferences(
        sortRawValue: String,
        rawStatusJSON: String,
        rawHiddenTagJSON: String
    ) -> EntityListPreferences {
        let sort = EntityListSortOption(rawValue: sortRawValue) ?? .priceHighToLow
        let hiddenStatusFilters = (try? JSONDecoder().decode([EntityListStatusFilter].self, from: Data(rawStatusJSON.utf8))) ?? []
        let hiddenTagIDs = (try? JSONDecoder().decode([RecordID].self, from: Data(rawHiddenTagJSON.utf8))) ?? []
        return EntityListPreferences(
            sort: sort,
            hiddenStatusFilters: hiddenStatusFilters,
            hiddenTagIDs: hiddenTagIDs
        )
    }
}
