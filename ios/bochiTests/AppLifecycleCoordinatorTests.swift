import Foundation
import Testing
@testable import bochi

@MainActor
struct AppLifecycleCoordinatorTests {
    // Behaviour: returning to the foreground should materialize any earned
    // vault interest before sync reads local mutations to push them.
    @Test func activationWorkAccruesVaultInterestBeforeSyncRefresh() async {
        let recorder = ForegroundActivationRecorder()
        let userID = "user-123"
        let activatedAt = Date(timeIntervalSince1970: 1_798_000_000)

        await AppActivationLifecycleCoordinator.runActivationWork(
            syncManager: recorder,
            tradeStore: recorder,
            ownerID: userID,
            now: activatedAt
        )

        #expect(recorder.events == ["vaultInterest", "syncRefresh"])
        #expect(recorder.vaultInterestDate == activatedAt)
        #expect(recorder.vaultInterestShouldNotifySync == true)
        #expect(recorder.pulledOwnerIDs == [userID])
    }

    // Behaviour: returning to the foreground while signed out should still let
    // local vault interest settle without attempting a remote refresh.
    @Test func activationWorkWithoutOwnerSkipsSyncRefresh() async {
        let recorder = ForegroundActivationRecorder()

        await AppActivationLifecycleCoordinator.runActivationWork(
            syncManager: recorder,
            tradeStore: recorder,
            ownerID: nil
        )

        #expect(recorder.events == ["vaultInterest"])
        #expect(recorder.pulledOwnerIDs.isEmpty)
    }

    // Behaviour: a queued task notification should open the task form once and
    // clear the durable route handoff so later activations do not reopen it.
    @Test func notificationTaskRouteOpensTaskFormOnce() {
        let routeStore = InMemoryNotificationRouteStore()
        let appNavigationStore = AppNavigationStore()

        routeStore.queueRoute(.task("task-123"), notifyObservers: false)
        NotificationRouteLifecycleCoordinator.activateQueuedRoute(
            routeStore: routeStore,
            appNavigationStore: appNavigationStore
        )

        #expect(appNavigationStore.selectedTab == .earn)
        #expect(appNavigationStore.pendingEntityFormRequest?.route == .task("task-123"))
        #expect(routeStore.consumeQueuedRoute() == nil)
    }

    // Behaviour: recurring task reminders use the same root navigation handoff
    // as task reminders so either notification type lands in the earn flow.
    @Test func notificationRecurringTaskRouteOpensRecurringTaskForm() {
        let routeStore = InMemoryNotificationRouteStore()
        let appNavigationStore = AppNavigationStore()

        routeStore.queueRoute(.recurringTask("recurringTask-123"), notifyObservers: false)
        NotificationRouteLifecycleCoordinator.activateQueuedRoute(
            routeStore: routeStore,
            appNavigationStore: appNavigationStore
        )

        #expect(appNavigationStore.selectedTab == .earn)
        #expect(appNavigationStore.pendingEntityFormRequest?.route == .recurringTask("recurringTask-123"))
    }

    // Behaviour: only edits for the active signed-in owner should reset the
    // mutation debounce that eventually pushes local changes.
    @Test func syncMutationLifecycleIgnoresMutationsForOtherOwners() {
        let userID = "user-123"
        let currentTrigger = SyncMutationLifecycleTrigger(ownerID: userID, revision: 1)
        let nextTrigger = SyncMutationLifecycleCoordinator.trigger(
            after: SyncMutation(ownerID: "other-user", entityKind: .tasks, recordIDs: ["task-1"]),
            activeOwnerID: userID,
            currentTrigger: currentTrigger
        )

        #expect(nextTrigger == currentTrigger)
    }

    // Behaviour: a dirty mutation for the active owner should wake sync after
    // the debounce window so local edits are backed up without a manual tap.
    @Test func syncMutationLifecycleRunsDebouncedSync() async {
        let userID = "user-123"
        let trigger = SyncMutationLifecycleCoordinator.trigger(
            after: SyncMutation(ownerID: userID, entityKind: .tasks, recordIDs: ["task-1"]),
            activeOwnerID: userID,
            currentTrigger: SyncMutationLifecycleTrigger(ownerID: userID, revision: 0)
        )
        let recorder = SyncMutationRecorder()

        #expect(trigger == SyncMutationLifecycleTrigger(ownerID: userID, revision: 1))

        await SyncMutationLifecycleCoordinator.runDebouncedSync(
            syncManager: recorder,
            debounceDuration: .zero
        )

        #expect(recorder.syncCount == 1)
    }

    // Behaviour: the background pull lifecycle asks sync to refresh the same
    // owner captured when the lifecycle task started.
    @Test func backgroundPullLifecycleRefreshesCapturedOwner() async {
        let recorder = ForegroundActivationRecorder()
        let userID = "user-123"

        await SyncBackgroundPullLifecycleCoordinator.runPull(
            syncManager: recorder,
            ownerID: userID
        )

        #expect(recorder.pulledOwnerIDs == [userID])
    }

    // Behaviour: the full-sync reset lifecycle marks the captured owner for a
    // later full pull instead of doing network work itself.
    @Test func fullSyncResetLifecycleMarksCapturedOwner() {
        let recorder = ForegroundActivationRecorder()
        let userID = "user-123"

        SyncFullSyncResetLifecycleCoordinator.runReset(
            syncManager: recorder,
            ownerID: userID
        )

        #expect(recorder.fullSyncResetOwnerIDs == [userID])
    }

    // Behaviour: once auth reconciliation has moved stores to a signed-in
    // owner, the sync-session lifecycle performs the initial backup/restore.
    @Test func syncSessionLifecycleStartsInitialSyncForSignedInOwner() async {
        let recorder = SyncStartRecorder()

        await SyncSessionLifecycleCoordinator.runInitialSync(
            syncManager: recorder,
            session: SyncSession(ownerID: "user-123", revision: 1)
        )

        #expect(recorder.syncCount == 1)
    }

    // Behaviour: a signed-out session should not attempt remote sync work.
    @Test func syncSessionLifecycleSkipsSignedOutSession() async {
        let recorder = SyncStartRecorder()

        await SyncSessionLifecycleCoordinator.runInitialSync(
            syncManager: recorder,
            session: SyncSession(ownerID: nil, revision: 1)
        )

        #expect(recorder.syncCount == 0)
    }

    // Behaviour: once bootstrap has decoded a saved token, owner-scoped stores
    // should switch to cached account rows even while network auth is still
    // reconciling account/settings state.
    @Test func authSessionLifecycleRestoresCachedOwnerDuringBootstrap() {
        let recorder = AuthSessionRecorder()

        AuthSessionLifecycleCoordinator.reconcile(
            trigger: AuthSessionLifecycleTrigger(isBootstrapping: true, userID: "user-123"),
            syncManager: recorder
        )

        #expect(recorder.events == ["cached:user-123"])
    }

    // Behaviour: nil user state during bootstrap is just "not decoded yet",
    // so the lifecycle should not switch to signed-out local rows until the
    // auth bootstrap task has actually settled.
    @Test func authSessionLifecycleDoesNotSignOutDuringBootstrap() {
        let recorder = AuthSessionRecorder()

        AuthSessionLifecycleCoordinator.reconcile(
            trigger: AuthSessionLifecycleTrigger(isBootstrapping: true, userID: nil),
            syncManager: recorder
        )

        #expect(recorder.events.isEmpty)
    }

    // Behaviour: once account deletion succeeds, local account rows should be
    // purged and any pending notifications for that account's reminders should
    // be canceled.
    @Test func accountDeletionLifecyclePurgesLocalDataAndCancelsReminderNotifications() {
        let cleaner = AccountDeletionCleanupRecorder(
            result: AccountDeletionCleanupResult(reminderIDs: ["reminder-1", "reminder-2"])
        )
        let notificationCanceller = AccountDeletionNotificationRecorder()

        AccountDeletionLifecycleCoordinator.reconcile(
            event: AccountDeletionEvent(userID: "user-123", revision: 1),
            dataCleaner: cleaner,
            notificationCanceller: notificationCanceller
        )

        #expect(cleaner.deletedUserIDs == ["user-123"])
        #expect(notificationCanceller.canceledReminderIDs == ["reminder-1", "reminder-2"])
    }

    // Behaviour: deleting an account locally should remove only that account's
    // owner-scoped rows and sync metadata, leaving signed-out local data alone.
    @Test func ownerDataDeletionServiceRemovesOnlyDeletedAccountRows() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("owner-account-deletion")
        let service = OwnerDataDeletionService(storageURL: storageURL)
        let database = AppDatabase.shared
        let deletedOwner = "deleted-user"
        let localOwner = StorageOwner.local

        _ = try database.connection(at: storageURL)
        try database.transaction(at: storageURL) { db in
            try database.execute(
                """
                INSERT INTO tasks (
                    id, owner_id, recurring, name, description, created_at, updated_at, deleted_at,
                    base_price, due_date, min_daily_frequency, lockout_duration_seconds, pinned, hidden,
                    timer_mode, timer_id, server_revision
                )
                VALUES (?, ?, 0, 'Remote task', '', 1, 1, NULL, 1, NULL, NULL, NULL, 0, 0, NULL, NULL, 0),
                       (?, ?, 0, 'Local task', '', 1, 1, NULL, 1, NULL, NULL, NULL, 0, 0, NULL, NULL, 0)
                """,
                bindings: [
                    .text("task-deleted"), .text(deletedOwner),
                    .text("task-local"), .text(localOwner)
                ],
                on: db
            )
            try database.execute(
                """
                INSERT INTO reminders (
                    id, owner_id, task_id, recurring_task_id, scheduled_at,
                    repeat_value, repeat_unit, created_at, updated_at, deleted_at
                )
                VALUES ('reminder-deleted', ?, 'task-deleted', NULL, 2, NULL, NULL, 1, 1, NULL),
                       ('reminder-local', ?, 'task-local', NULL, 2, NULL, NULL, 1, 1, NULL)
                """,
                bindings: [.text(deletedOwner), .text(localOwner)],
                on: db
            )
            try database.execute(
                """
                INSERT INTO sync_state (
                    user_id, last_sync_server_time, last_full_sync_at,
                    full_sync_required, last_sync_cursor, last_mutation_generation
                )
                VALUES (?, 1, 1, 0, 'cursor', 2)
                """,
                bindings: [.text(deletedOwner)],
                on: db
            )
            try database.execute(
                """
                INSERT INTO dirty_records (user_id, entity_kind, record_id, mutation_generation)
                VALUES (?, 'tasks', 'task-deleted', 2)
                """,
                bindings: [.text(deletedOwner)],
                on: db
            )
        }

        let result = try service.deleteAccountData(userID: deletedOwner)

        #expect(result.reminderIDs == ["reminder-deleted"])

        let counts = try database.transaction(at: storageURL) { db in
            (
                deletedTasks: try database.queryOne(
                    "SELECT COUNT(*) FROM tasks WHERE owner_id = ?",
                    bindings: [.text(deletedOwner)],
                    on: db
                ) { row in SQLiteColumn.int(row, index: 0) } ?? -1,
                localTasks: try database.queryOne(
                    "SELECT COUNT(*) FROM tasks WHERE owner_id = ?",
                    bindings: [.text(localOwner)],
                    on: db
                ) { row in SQLiteColumn.int(row, index: 0) } ?? -1,
                deletedSyncRows: try database.queryOne(
                    "SELECT COUNT(*) FROM sync_state WHERE user_id = ?",
                    bindings: [.text(deletedOwner)],
                    on: db
                ) { row in SQLiteColumn.int(row, index: 0) } ?? -1,
                deletedDirtyRows: try database.queryOne(
                    "SELECT COUNT(*) FROM dirty_records WHERE user_id = ?",
                    bindings: [.text(deletedOwner)],
                    on: db
                ) { row in SQLiteColumn.int(row, index: 0) } ?? -1
            )
        }

        #expect(counts.deletedTasks == 0)
        #expect(counts.localTasks == 1)
        #expect(counts.deletedSyncRows == 0)
        #expect(counts.deletedDirtyRows == 0)
    }
}

@MainActor
private final class ForegroundActivationRecorder: SyncBackgroundPulling, SyncFullSyncResetting, VaultInterestAccruing {
    private(set) var events: [String] = []
    private(set) var pulledOwnerIDs: [String] = []
    private(set) var fullSyncResetOwnerIDs: [String] = []
    private(set) var vaultInterestDate: Date?
    private(set) var vaultInterestShouldNotifySync: Bool?

    func accrueVaultInterestIfNeeded(now: Date, shouldNotifySync: Bool) {
        events.append("vaultInterest")
        vaultInterestDate = now
        vaultInterestShouldNotifySync = shouldNotifySync
    }

    func pullRemoteChangesNow(for userID: String) async {
        events.append("syncRefresh")
        pulledOwnerIDs.append(userID)
    }

    func forceFullSyncOnNextRun(for userID: String) {
        fullSyncResetOwnerIDs.append(userID)
    }
}

@MainActor
private final class InMemoryNotificationRouteStore: NotificationEntityRouteStoring {
    private var queuedRoute: NotificationEntityRoute?

    func queueRoute(_ route: NotificationEntityRoute, notifyObservers: Bool) {
        queuedRoute = route
    }

    func consumeQueuedRoute() -> NotificationEntityRoute? {
        defer { queuedRoute = nil }
        return queuedRoute
    }
}

@MainActor
private final class SyncMutationRecorder: SyncMutationSyncing {
    private(set) var syncCount = 0

    func syncNow() async {
        syncCount += 1
    }
}

@MainActor
private final class SyncStartRecorder: SyncSessionStarting {
    private(set) var syncCount = 0

    func syncNow() async {
        syncCount += 1
    }
}

@MainActor
private final class AuthSessionRecorder: AuthSessionUpdating {
    private(set) var events: [String] = []

    func restoreCachedSession(userID: String) {
        events.append("cached:\(userID)")
    }

    func updateSession(userID: String?) {
        events.append("settled:\(userID ?? "nil")")
    }
}

@MainActor
private final class AccountDeletionCleanupRecorder: AccountDeletionDataCleaning {
    private(set) var deletedUserIDs: [String] = []
    private let result: AccountDeletionCleanupResult

    init(result: AccountDeletionCleanupResult) {
        self.result = result
    }

    func deleteLocalAccountData(for userID: String) throws -> AccountDeletionCleanupResult {
        deletedUserIDs.append(userID)
        return result
    }
}

@MainActor
private final class AccountDeletionNotificationRecorder: AccountDeletionNotificationCancelling {
    private(set) var canceledReminderIDs: [RecordID] = []

    func cancelNotifications(for reminderIDs: [RecordID]) {
        canceledReminderIDs = reminderIDs
    }
}
