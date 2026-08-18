import Foundation
import Testing
@testable import bochi

@MainActor
struct SyncManagerTests {
    private final class MockSyncAPIClient: SyncAPIClient, @unchecked Sendable {
        var pullHandler: @Sendable (String?, String) async throws -> SyncResponse
        var pushHandler: @Sendable (SyncPushRequest, String) async throws -> SyncResponse

        private(set) var pullCalls: [(String?, String)] = []
        private(set) var pushCalls: [(SyncPushRequest, String)] = []

        init(
            pullHandler: @escaping @Sendable (String?, String) async throws -> SyncResponse,
            pushHandler: @escaping @Sendable (SyncPushRequest, String) async throws -> SyncResponse
        ) {
            self.pullHandler = pullHandler
            self.pushHandler = pushHandler
        }

        func pullSync(cursor: String?, accessToken: String) async throws -> SyncResponse {
            pullCalls.append((cursor, accessToken))
            return try await pullHandler(cursor, accessToken)
        }

        func pushSync(_ request: SyncPushRequest, accessToken: String) async throws -> SyncResponse {
            pushCalls.append((request, accessToken))
            return try await pushHandler(request, accessToken)
        }
    }

    private struct TestContext {
        let syncManager: SyncManager
        let syncStateStore: SyncStateStore
        let timerStore: TimerStore
        let taskStore: TaskStore
        let taskDependencyStore: TaskDependencyStore
        let rewardDependencyStore: RewardDependencyStore
        let recurringTaskStore: RecurringTaskStore
        let rewardStore: RewardStore
        let tradeStore: TradeStore
        let tagStore: TagStore
        let balanceStore: BalanceStore
        let userSettingsStore: UserSettingsStore
        let reminderStore: ReminderStore
        let listPreferencesStore: ListPreferencesStore
        let syncAPIClient: MockSyncAPIClient
    }

    private enum TestFailure: Error {
        case pushRejected
    }

    private let userID = "user-123"
    private let timestamp = "2026-04-18T12:00:00.000000"

    private func makeContext(
        pullResponse: SyncResponse,
        pushResponse: SyncResponse? = nil
    ) async throws -> TestContext {
        try await makeContext(
            pullHandler: { _, _ in pullResponse },
            pushHandler: { _, _ in pushResponse ?? pullResponse }
        )
    }

    private func makeContext(
        pullHandler: @escaping @Sendable (String?, String) async throws -> SyncResponse,
        pushHandler: @escaping @Sendable (SyncPushRequest, String) async throws -> SyncResponse
    ) async throws -> TestContext {
        let authAPIClient = MockAuthAPIClient()
        let tokenStorage = MockTokenStorage()
        let entitlementClient = MockAppleEntitlementClient()
        let tokens = TestHelpers.makeTokens(userId: userID)

        authAPIClient.signInWithAppleResult = .success(tokens)
        authAPIClient.currentAccountResult = .success(TestHelpers.makeCurrentAccount(email: "user@example.com"))

        let authManager = AuthManager(
            apiClient: authAPIClient,
            tokenStorage: tokenStorage,
            appleEntitlementClient: entitlementClient
        )
        try await authManager.signInWithApple(
            identityToken: "identity-token",
            email: "user@example.com",
            nonce: "nonce"
        )

        let storageURL = TestHelpers.makeTemporaryFileURL("sync-manager")
        let timerStore = TimerStore(storageURL: storageURL)
        let taskStore = TaskStore(storageURL: storageURL)
        let taskDependencyStore = TaskDependencyStore(storageURL: storageURL)
        let rewardDependencyStore = RewardDependencyStore(storageURL: storageURL)
        let recurringTaskStore = RecurringTaskStore(storageURL: storageURL)
        let rewardStore = RewardStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let tagStore = TagStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        let userSettingsStore = UserSettingsStore(storageURL: storageURL)
        let reminderStore = ReminderStore(storageURL: storageURL)
        let listPreferencesStore = ListPreferencesStore(storageURL: storageURL)
        let syncStateStore = SyncStateStore(storageURL: storageURL)

        let syncAPIClient = MockSyncAPIClient(
            pullHandler: pullHandler,
            pushHandler: pushHandler
        )

        let syncManager = SyncManager(
            apiClient: syncAPIClient,
            authManager: authManager,
            syncStateStore: syncStateStore,
            timerStore: timerStore,
            taskStore: taskStore,
            taskDependencyStore: taskDependencyStore,
            rewardDependencyStore: rewardDependencyStore,
            recurringTaskStore: recurringTaskStore,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            tagStore: tagStore,
            balanceStore: balanceStore,
            userSettingsStore: userSettingsStore,
            reminderStore: reminderStore,
            listPreferencesStore: listPreferencesStore
        )

        return TestContext(
            syncManager: syncManager,
            syncStateStore: syncStateStore,
            timerStore: timerStore,
            taskStore: taskStore,
            taskDependencyStore: taskDependencyStore,
            rewardDependencyStore: rewardDependencyStore,
            recurringTaskStore: recurringTaskStore,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            tagStore: tagStore,
            balanceStore: balanceStore,
            userSettingsStore: userSettingsStore,
            reminderStore: reminderStore,
            listPreferencesStore: listPreferencesStore,
            syncAPIClient: syncAPIClient
        )
    }

    private func makeResponse(
        timers: [SyncTimerRecord] = [],
        tasks: [SyncTaskRecord] = [],
        recurringTasks: [SyncRecurringTaskRecord] = [],
        trades: [SyncTradeRecord] = [],
        tags: [SyncTagRecord] = [],
        taskTags: [SyncTaskTagRecord] = [],
        taskTaskDependencies: [SyncTaskTaskDependencyRecord] = [],
        taskRecurringTaskDependencies: [SyncTaskRecurringTaskDependencyRecord] = [],
        recurringTaskTags: [SyncRecurringTaskTagRecord] = [],
        rewards: [SyncRewardRecord] = [],
        rewardTaskDependencies: [SyncRewardTaskDependencyRecord] = [],
        rewardRecurringTaskDependencies: [SyncRewardRecurringTaskDependencyRecord] = [],
        rewardTags: [SyncRewardTagRecord] = [],
        balance: SyncBalanceRecord = SyncBalanceRecord(pointBalance: 0),
        serverCursor: String = "cursor-123",
        serverTime: String = "2026-04-18T12:00:00.000000",
        themePalettes: SyncThemePalettes? = nil
    ) -> SyncResponse {
        SyncResponse(
            timers: timers,
            tasks: tasks,
            recurringTasks: recurringTasks,
            trades: trades,
            tags: tags,
            taskTags: taskTags,
            taskTaskDependencies: taskTaskDependencies,
            taskRecurringTaskDependencies: taskRecurringTaskDependencies,
            recurringTaskTags: recurringTaskTags,
            rewards: rewards,
            rewardTaskDependencies: rewardTaskDependencies,
            rewardRecurringTaskDependencies: rewardRecurringTaskDependencies,
            rewardTags: rewardTags,
            balance: balance,
            serverCursor: serverCursor,
            serverTime: serverTime,
            email: "user@example.com",
            isPremium: false,
            themePalettes: themePalettes ?? SyncThemePalettes(main: .porcelain, accent: .semantic)
        )
    }

    private func makeTaskRecord(
        id: String = "task-1",
        name: String = "Remote Task",
        description: String = "",
        basePrice: Int = 240,
        dueDate: String? = nil,
        pinned: Bool = false,
        hidden: Bool = false,
        updatedAt: String? = nil,
        deletedAt: String? = nil,
        serverRevision: Int64? = nil
    ) -> SyncTaskRecord {
        SyncTaskRecord(
            id: id,
            name: name,
            description: description,
            createdAt: timestamp,
            updatedAt: updatedAt ?? timestamp,
            deletedAt: deletedAt,
            basePrice: basePrice,
            dueDate: dueDate,
            pinned: pinned,
            hidden: hidden,
            serverRevision: serverRevision
        )
    }

    private func makeRecurringTaskRecord(
        id: String = "recurringTask-1",
        name: String = "Remote RecurringTask",
        description: String = "",
        frequency: Double? = nil,
        lockoutDurationSeconds: Int? = nil,
        basePrice: Int = 120,
        pinned: Bool = false,
        hidden: Bool = false,
        updatedAt: String? = nil,
        deletedAt: String? = nil,
        serverRevision: Int64? = nil
    ) -> SyncRecurringTaskRecord {
        SyncRecurringTaskRecord(
            id: id,
            name: name,
            description: description,
            createdAt: timestamp,
            updatedAt: updatedAt ?? timestamp,
            deletedAt: deletedAt,
            minDailyFrequency: frequency,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: basePrice,
            pinned: pinned,
            hidden: hidden,
            serverRevision: serverRevision
        )
    }

    private func makeRewardRecord(
        id: String = "reward-1",
        recurring: Bool = true,
        name: String = "Remote Reward",
        description: String = "",
        maxFrequency: Double? = nil,
        lockoutDurationSeconds: Int? = nil,
        basePrice: Int = 500,
        pinned: Bool = false,
        hidden: Bool = false,
        updatedAt: String? = nil,
        deletedAt: String? = nil,
        serverRevision: Int64? = nil
    ) -> SyncRewardRecord {
        SyncRewardRecord(
            id: id,
            recurring: recurring,
            name: name,
            description: description,
            createdAt: timestamp,
            updatedAt: updatedAt ?? timestamp,
            deletedAt: deletedAt,
            maxDailyFrequency: maxFrequency,
            lockoutDurationSeconds: lockoutDurationSeconds,
            basePrice: basePrice,
            pinned: pinned,
            hidden: hidden,
            serverRevision: serverRevision
        )
    }

    // Behaviour: a cold launch with cached account credentials should show the
    // account's local tasks immediately, before auth refresh or settings sync
    // publishes the signed-in sync session.
    @Test func cachedSessionShowsAccountTasksBeforeBootstrapSettles() async throws {
        let context = try await makeContext(pullResponse: makeResponse())
        let accountTaskStore = TaskStore(storageURL: context.syncStateStore.databaseURL, initialOwnerID: userID)
        _ = accountTaskStore.addTask(
            id: "cached-task",
            name: "Cached Account Task",
            shouldNotifySync: false
        )

        #expect(context.taskStore.activeTasks.isEmpty)

        context.syncManager.restoreCachedSession(userID: userID)

        #expect(context.taskStore.activeTasks.map(\.name) == ["Cached Account Task"])
        #expect(context.taskStore.currentOwnerID == userID)
        #expect(context.syncManager.syncSession == SyncSession(ownerID: nil, revision: 0))
        #expect(context.syncAPIClient.pullCalls.isEmpty)
        #expect(context.syncAPIClient.pushCalls.isEmpty)
    }

    // Behaviour: using cached account data for first paint should not skip the
    // normal local-device migration once auth bootstrap confirms the account.
    @Test func cachedSessionDefersLocalMigrationUntilBootstrapSettles() async throws {
        let context = try await makeContext(pullResponse: makeResponse())
        _ = context.taskStore.addTask(
            id: "local-task",
            name: "Local Draft Task",
            shouldNotifySync: false
        )

        context.syncManager.restoreCachedSession(userID: userID)
        #expect(context.taskStore.activeTasks.isEmpty)

        context.syncManager.updateSession(userID: userID)

        #expect(context.taskStore.activeTasks.map(\.name) == ["Local Draft Task"])
        #expect(context.syncManager.syncSession == SyncSession(ownerID: userID, revision: 1))
    }

    // Behaviour: signing in after rich signed-out usage should move the whole
    // local graph into the account owner and queue only synced entities for push.
    @Test func signingInMigratesLocalLedgerGraphAndQueuesSyncedRecords() async throws {
        let context = try await makeContext(
            pullResponse: makeResponse(serverCursor: "migration-pull-cursor"),
            pushResponse: makeResponse(serverCursor: "migration-push-cursor")
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let existingAccountTimer = BochiTimer(
            id: "account-timer",
            name: "Account Timer",
            intervals: [TimerInterval(name: "Remote", durationSeconds: 60)],
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            serverRevision: 10
        )
        let accountTimerStore = TimerStore(storageURL: context.syncStateStore.databaseURL)
        accountTimerStore.setCurrentOwner(userID)
        try accountTimerStore.persistReplacedTimers([existingAccountTimer])

        let localTimer = try #require(context.timerStore.addTimer(
            id: "local-timer",
            name: "Local Timer",
            intervals: [TimerInterval(name: "Focus", durationSeconds: 1_500)],
            now: now
        ))
        let completedTask = try #require(context.taskStore.addTask(
            id: "completed-task",
            name: "Offline Task",
            basePrice: 100,
            createdAt: now,
            updatedAt: now
        ))
        let dependentTask = try #require(context.taskStore.addTask(
            id: "dependent-task",
            name: "Offline Dependent Task",
            basePrice: 120,
            createdAt: now.addingTimeInterval(1),
            updatedAt: now.addingTimeInterval(1)
        ))
        let recurringTask = try #require(context.recurringTaskStore.addRecurringTask(
            id: "recurring-task",
            name: "Offline Recurring Task",
            frequency: 1,
            basePrice: 80,
            createdAt: now.addingTimeInterval(2),
            updatedAt: now.addingTimeInterval(2)
        ))
        let reward = try #require(context.rewardStore.addReward(
            id: "reward",
            name: "Offline Reward",
            basePrice: 60,
            createdAt: now.addingTimeInterval(3),
            updatedAt: now.addingTimeInterval(3)
        ))
        let tag = try #require(context.tagStore.addTag(
            id: "tag",
            name: "Offline Tag",
            colorHex: "#336699",
            createdAt: now.addingTimeInterval(4),
            updatedAt: now.addingTimeInterval(4)
        ))

        context.tagStore.addTagToTask(tagId: tag.id, taskId: completedTask.id, createdAt: now, updatedAt: now)
        context.tagStore.addTagToRecurringTask(tagId: tag.id, recurringTaskId: recurringTask.id, createdAt: now, updatedAt: now)
        context.tagStore.addTagToReward(tagId: tag.id, rewardId: reward.id, createdAt: now, updatedAt: now)

        let taskTaskDependency = TaskTaskDependency(
            taskId: dependentTask.id,
            dependsOnTaskId: completedTask.id,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        let taskRecurringTaskDependency = TaskRecurringTaskDependency(
            taskId: dependentTask.id,
            recurringTaskId: recurringTask.id,
            requiredCompletions: 1,
            baselineCompletionCount: 0,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        context.taskDependencyStore.replaceDependencies(
            for: dependentTask.id,
            taskDependencies: [taskTaskDependency],
            recurringTaskDependencies: [taskRecurringTaskDependency]
        )

        let rewardTaskDependency = RewardTaskDependency(
            rewardId: reward.id,
            dependsOnTaskId: completedTask.id,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        let rewardRecurringTaskDependency = RewardRecurringTaskDependency(
            rewardId: reward.id,
            recurringTaskId: recurringTask.id,
            requiredCompletions: 1,
            baselineCompletionCount: 0,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        context.rewardDependencyStore.replaceDependencies(
            for: reward.id,
            taskDependencies: [rewardTaskDependency],
            recurringTaskDependencies: [rewardRecurringTaskDependency]
        )

        context.tradeStore.addTaskTrade(
            id: "task-trade",
            taskId: completedTask.id,
            amount: 100,
            createdAt: now.addingTimeInterval(10)
        )
        context.tradeStore.addRecurringTaskTrade(
            id: "recurring-task-trade",
            recurringTaskId: recurringTask.id,
            amount: 80,
            createdAt: now.addingTimeInterval(20)
        )
        context.tradeStore.addRewardPurchase(
            id: "reward-purchase",
            rewardId: reward.id,
            amount: -60,
            createdAt: now.addingTimeInterval(30)
        )
        context.tradeStore.addVaultDeposit(
            id: "vault-deposit",
            amount: 30,
            createdAt: now.addingTimeInterval(40)
        )
        context.tradeStore.addVaultInterest(
            id: "vault-interest",
            vaultAmountMicro: VaultAmount.microUnits(forWholeBochi: 1),
            vaultInterestHour: now,
            createdAt: now.addingTimeInterval(50)
        )
        context.tradeStore.addVaultRewardPurchases(
            entries: [(id: "vault-reward-purchase", amount: 10, adjustmentBaseAmount: 10)],
            rewardId: reward.id,
            createdAt: now.addingTimeInterval(60)
        )
        let refund = try #require(context.tradeStore.refundTrade(
            id: "reward-purchase",
            refundedAt: now.addingTimeInterval(70)
        ))

        context.reminderStore.replaceReminders(
            for: .task(completedTask.id),
            with: [
                ReminderDraft(
                    id: "task-reminder",
                    scheduledAt: now.addingTimeInterval(3_600),
                    recurrence: ReminderRecurrence(intervalValue: 1, unit: .days)
                )
            ]
        )
        context.reminderStore.replaceReminders(
            for: .recurringTask(recurringTask.id),
            with: [
                ReminderDraft(
                    id: "recurring-task-reminder",
                    scheduledAt: now.addingTimeInterval(7_200)
                )
            ]
        )
        context.listPreferencesStore.setTaskSort(.newestToOldest)
        context.listPreferencesStore.toggleTaskTag(tag.id)
        context.listPreferencesStore.toggleTaskStatus(.completed)
        context.userSettingsStore.setThemePalettes(
            BochiThemePalettePreferences(main: .mint, accent: .palette(.jade))
        )

        context.syncManager.updateSession(userID: userID)

        #expect(Set(context.timerStore.timers.map(\.id)) == Set([existingAccountTimer.id, localTimer.id]))
        #expect(Set(context.taskStore.activeTasks.map(\.id)) == Set([completedTask.id, dependentTask.id]))
        #expect(context.recurringTaskStore.activeRecurringTasks.map(\.id) == [recurringTask.id])
        #expect(context.rewardStore.activeRewards.map(\.id) == [reward.id])
        #expect(context.tagStore.tags.map(\.id) == [tag.id])
        #expect(context.tagStore.taskTags.map(\.id) == [RecordID("\(completedTask.id):\(tag.id)")])
        #expect(context.tagStore.recurringTaskTags.map(\.id) == [RecordID("\(recurringTask.id):\(tag.id)")])
        #expect(context.tagStore.rewardTags.map(\.id) == [RecordID("\(reward.id):\(tag.id)")])
        #expect(context.taskDependencyStore.taskTaskDependencies.map(\.id) == [taskTaskDependency.id])
        #expect(context.taskDependencyStore.taskRecurringTaskDependencies.map(\.id) == [taskRecurringTaskDependency.id])
        #expect(context.rewardDependencyStore.rewardTaskDependencies.map(\.id) == [rewardTaskDependency.id])
        #expect(context.rewardDependencyStore.rewardRecurringTaskDependencies.map(\.id) == [rewardRecurringTaskDependency.id])
        #expect(context.tradeStore.trades.count == 7)
        #expect(context.tradeStore.trades.contains { $0.tradeKind == .vaultDeposit })
        #expect(context.tradeStore.trades.contains { $0.tradeKind == .vaultInterest })
        #expect(context.tradeStore.trades.contains { $0.tradeKind == .vaultRewardPurchase })
        #expect(context.tradeStore.trades.contains { $0.id == refund.id && $0.refundsTradeId == "reward-purchase" })
        #expect(context.balanceStore.balance == 150)
        #expect(context.reminderStore.reminders.map(\.id) == ["task-reminder", "recurring-task-reminder"])
        #expect(context.listPreferencesStore.taskPreferences.sort == .newestToOldest)
        #expect(context.listPreferencesStore.taskPreferences.hiddenStatusFilters == [.completed])
        #expect(context.listPreferencesStore.taskPreferences.hiddenTagIDs == [tag.id])
        #expect(context.userSettingsStore.themePalettes == BochiThemePalettePreferences(main: .mint, accent: .palette(.jade)))

        let dirtyState = context.syncStateStore.state(for: userID).dirty
        let dirtyIDs: ([SyncStateStore.DirtyRecordVersion]) -> Set<RecordID> = { Set($0.map(\.id)) }
        #expect(dirtyIDs(dirtyState.timers) == Set([localTimer.id]))
        #expect(dirtyIDs(dirtyState.tasks) == Set([completedTask.id, dependentTask.id]))
        #expect(dirtyIDs(dirtyState.recurringTasks) == Set([recurringTask.id]))
        #expect(dirtyIDs(dirtyState.rewards) == Set([reward.id]))
        #expect(dirtyIDs(dirtyState.trades) == Set(context.tradeStore.trades.map(\.id)))
        #expect(dirtyIDs(dirtyState.tags) == Set([tag.id]))
        #expect(dirtyIDs(dirtyState.taskTags) == Set(context.tagStore.taskTags.map(\.id)))
        #expect(dirtyIDs(dirtyState.recurringTaskTags) == Set(context.tagStore.recurringTaskTags.map(\.id)))
        #expect(dirtyIDs(dirtyState.rewardTags) == Set(context.tagStore.rewardTags.map(\.id)))
        #expect(dirtyIDs(dirtyState.taskTaskDependencies) == Set([taskTaskDependency.id]))
        #expect(dirtyIDs(dirtyState.taskRecurringTaskDependencies) == Set([taskRecurringTaskDependency.id]))
        #expect(dirtyIDs(dirtyState.rewardTaskDependencies) == Set([rewardTaskDependency.id]))
        #expect(dirtyIDs(dirtyState.rewardRecurringTaskDependencies) == Set([rewardRecurringTaskDependency.id]))
        #expect(dirtyState.themePalettes)

        await context.syncManager.syncNow()

        let operationKinds = try #require(context.syncAPIClient.pushCalls.last?.0.operations.map(\.kind))
        #expect(operationKinds.filter { $0 == "upsertTimer" }.count == 1)
        #expect(operationKinds.filter { $0 == "upsertTask" }.count == 2)
        #expect(operationKinds.filter { $0 == "upsertTaskTaskDependency" }.count == 1)
        #expect(operationKinds.filter { $0 == "upsertTaskRecurringTaskDependency" }.count == 1)
        #expect(operationKinds.filter { $0 == "upsertRecurringTask" }.count == 1)
        #expect(operationKinds.filter { $0 == "upsertReward" }.count == 1)
        #expect(operationKinds.filter { $0 == "upsertRewardTaskDependency" }.count == 1)
        #expect(operationKinds.filter { $0 == "upsertRewardRecurringTaskDependency" }.count == 1)
        #expect(operationKinds.filter { $0 == "upsertTrade" }.count == 7)
        #expect(operationKinds.filter { $0 == "upsertTag" }.count == 1)
        #expect(operationKinds.filter { $0 == "upsertTaskTag" }.count == 1)
        #expect(operationKinds.filter { $0 == "upsertRecurringTaskTag" }.count == 1)
        #expect(operationKinds.filter { $0 == "upsertRewardTag" }.count == 1)
        #expect(operationKinds.filter { $0 == "updateThemePalettes" }.count == 1)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: if one local category cannot be rewritten during sign-in, the
    // app should still enter the account owner and migrate the other categories.
    @Test func signingInContinuesWhenOneLocalCategoryCannotMigrate() async throws {
        let context = try await makeContext(pullResponse: makeResponse())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = try #require(context.taskStore.addTask(
            id: "task-with-corrupt-dependency",
            name: "Task",
            createdAt: now,
            updatedAt: now
        ))
        let recurringTask = try #require(context.recurringTaskStore.addRecurringTask(
            id: "recurring-for-corrupt-dependency",
            name: "Recurring",
            createdAt: now,
            updatedAt: now
        ))
        let reward = try #require(context.rewardStore.addReward(
            id: "reward-that-should-still-migrate",
            name: "Reward",
            createdAt: now,
            updatedAt: now
        ))

        try AppDatabase.shared.execute("PRAGMA ignore_check_constraints = ON", at: context.syncStateStore.databaseURL)
        defer {
            try? AppDatabase.shared.execute("PRAGMA ignore_check_constraints = OFF", at: context.syncStateStore.databaseURL)
        }
        try AppDatabase.shared.execute(
            """
            INSERT INTO task_recurring_task_dependencies (
                owner_id, task_id, recurring_task_id, required_completions,
                baseline_completion_count, created_at, updated_at, deleted_at, server_revision
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(StorageOwner.local),
                .text(task.id.rawValue),
                .text(recurringTask.id.rawValue),
                .int(0),
                .int(0),
                .double(now.timeIntervalSince1970),
                .double(now.timeIntervalSince1970),
                .null,
                .null
            ],
            at: context.syncStateStore.databaseURL
        )
        try AppDatabase.shared.execute("PRAGMA ignore_check_constraints = OFF", at: context.syncStateStore.databaseURL)

        context.syncManager.updateSession(userID: userID)

        #expect(context.syncManager.syncSession == SyncSession(ownerID: userID, revision: 1))
        #expect(context.taskStore.activeTasks.map(\.id) == [task.id])
        #expect(context.recurringTaskStore.activeRecurringTasks.map(\.id) == [recurringTask.id])
        #expect(context.rewardStore.activeRewards.map(\.id) == [reward.id])
        #expect(context.taskDependencyStore.taskRecurringTaskDependencies.isEmpty)

        let retainedLocalDependencyCount = try #require(try AppDatabase.shared.queryOne(
            """
            SELECT COUNT(*)
            FROM task_recurring_task_dependencies
            WHERE owner_id = ?
            """,
            bindings: [.text(StorageOwner.local)],
            at: context.syncStateStore.databaseURL
        ) { row in
            SQLiteColumn.int(row, index: 0)
        })
        #expect(retainedLocalDependencyCount == 1)
        #expect(context.syncStateStore.state(for: userID).dirty.taskRecurringTaskDependencies.isEmpty)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: anonymous and account vault interest for the same hour should
    // merge into one account row instead of failing the unique owner/hour index.
    @Test func signingInCombinesDuplicateVaultInterestHours() async throws {
        let context = try await makeContext(pullResponse: makeResponse())
        let hour = Date(timeIntervalSince1970: 1_800_000_000)
        let accountTradeStore = TradeStore(
            storageURL: context.syncStateStore.databaseURL,
            initialOwnerID: userID,
            accruesVaultInterestOnLoad: false
        )
        accountTradeStore.addVaultInterest(
            id: "account-interest",
            vaultAmountMicro: 1_000_000,
            vaultInterestHour: hour,
            createdAt: hour,
            shouldNotifySync: false
        )
        context.tradeStore.addVaultInterest(
            id: "local-duplicate-interest",
            vaultAmountMicro: 2_000_000,
            vaultInterestHour: hour,
            createdAt: hour.addingTimeInterval(60)
        )
        context.tradeStore.addVaultInterest(
            id: "local-next-hour-interest",
            vaultAmountMicro: 3_000_000,
            vaultInterestHour: hour.addingTimeInterval(3_600),
            createdAt: hour.addingTimeInterval(3_600)
        )

        context.syncManager.updateSession(userID: userID)

        #expect(context.tradeStore.trades.map(\.id) == ["account-interest", "local-next-hour-interest"])
        let combinedInterest = try #require(context.tradeStore.trades.first { $0.id == "account-interest" })
        #expect(combinedInterest.vaultAmountMicro == 3_000_000)
        let dirtyTradeIDs = Set(context.syncStateStore.state(for: userID).dirty.trades.map(\.id))
        #expect(dirtyTradeIDs == Set([RecordID("account-interest"), RecordID("local-next-hour-interest")]))

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: signing in after offline creation pushes the local base-price entity instead of replacing it with an empty pull.
    @Test func signingInMigratesLocalRecurringTaskAndPushesBasePrice() async throws {
        let context = try await makeContext(pullResponse: makeResponse())

        _ = context.recurringTaskStore.addRecurringTask(name: "Offline RecurringTask", frequency: 2.0, basePrice: 175)

        context.syncManager.updateSession(userID: userID)
        #expect(context.syncAPIClient.pullCalls.isEmpty)
        #expect(context.syncAPIClient.pushCalls.isEmpty)
        #expect(context.syncManager.syncSession == SyncSession(ownerID: userID, revision: 1))

        await context.syncManager.syncNow()

        #expect(context.recurringTaskStore.currentOwnerID == userID)
        #expect(context.syncAPIClient.pushCalls.count == 1)
        let pushedRecurringTask = try #require(context.syncAPIClient.pushCalls.first?.0.operations.first?.recurringTaskPayload)
        #expect(pushedRecurringTask.name == "Offline RecurringTask")
        #expect(pushedRecurringTask.minDailyFrequency == 2.0)
        #expect(pushedRecurringTask.basePrice == 175)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: when a full sync has been forced, passive foreground polling
    // performs the same replacement repair as a manual sync instead of merely
    // merging a no-cursor pull and checkpointing it.
    @Test func backgroundPullCompletesForcedFullSyncReplacement() async throws {
        let initialResponse = makeResponse(
            serverCursor: "initial-cursor",
            serverTime: "2026-04-18T12:00:00.000000"
        )
        let repairResponse = makeResponse(
            serverCursor: "repair-cursor",
            serverTime: "2026-04-19T12:00:00.000000"
        )
        let context = try await makeContext(pullResponse: initialResponse)

        context.syncManager.updateSession(userID: userID)
        await context.syncManager.syncNow()
        context.syncAPIClient.pullHandler = { _, _ in repairResponse }

        _ = context.taskStore.addTask(
            id: RecordID("stale-clean-task"),
            name: "Stale Clean Task",
            basePrice: 260,
            shouldNotifySync: false
        )
        #expect(context.taskStore.activeTasks.count == 1)

        context.syncStateStore.forceFullSyncOnNextRun(userID: userID)

        await context.syncManager.pullRemoteChangesNow(for: userID)

        let fullPullCall = try #require(context.syncAPIClient.pullCalls.last)
        #expect(fullPullCall.0 == nil)
        #expect(context.taskStore.activeTasks.isEmpty)

        let state = context.syncStateStore.state(for: userID)
        let completedAt = try #require(state.lastFullSyncAt)
        let repairTime = try #require(AppDateCoding.parseBackendTimestamp("2026-04-19T12:00:00.000000"))
        #expect(abs(completedAt.timeIntervalSince(repairTime)) < 0.001)
        #expect(!context.syncStateStore.shouldPerformFullSync(userID: userID, now: repairTime.addingTimeInterval(1)))

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: a clean full pull persists the remote base prices and recurring cadence for each entity type.
    @Test func fullPullPersistsBasePriceEntities() async throws {
        let response = makeResponse(
            tasks: [
                makeTaskRecord(basePrice: 275, pinned: true)
            ],
            recurringTasks: [
                makeRecurringTaskRecord(frequency: 3.0, lockoutDurationSeconds: 600, basePrice: 125)
            ],
            rewards: [
                makeRewardRecord(recurring: true, maxFrequency: 0.5, lockoutDurationSeconds: 3_600, basePrice: 850)
            ],
            serverCursor: "remote-cursor"
        )
        let context = try await makeContext(pullResponse: response)

        context.syncManager.updateSession(userID: userID)
        await context.syncManager.syncNow()

        let task = try #require(context.taskStore.activeTasks.first)
        #expect(task.basePrice == 275)
        #expect(task.pinned)

        let recurringTask = try #require(context.recurringTaskStore.activeRecurringTasks.first)
        #expect(recurringTask.basePrice == 125)
        #expect(recurringTask.frequency == 3.0)
        #expect(recurringTask.lockoutDurationSeconds == 600)

        let reward = try #require(context.rewardStore.activeRewards.first)
        #expect(reward.basePrice == 850)
        #expect(reward.maxFrequency == 0.5)
        #expect(reward.lockoutDurationSeconds == 3_600)
        #expect(context.syncStateStore.state(for: userID).lastSyncCursor == "remote-cursor")

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: local edits sync the user-entered base price directly while preserving recurring frequency fields.
    @Test func dirtyEntitiesPushBasePriceAndFrequencyFields() async throws {
        let context = try await makeContext(pullResponse: makeResponse(serverCursor: "base-cursor"))

        context.syncManager.updateSession(userID: userID)
        _ = context.taskStore.addTask(name: "Local Task", basePrice: 320)
        _ = context.recurringTaskStore.addRecurringTask(name: "Local RecurringTask", frequency: 4.0, basePrice: 90)
        _ = context.rewardStore.addReward(recurring: true, name: "Local Reward", maxFrequency: 0.25, basePrice: 1_000)

        await context.syncManager.syncNow()

        let request = try #require(context.syncAPIClient.pushCalls.last?.0)
        #expect(request.baseCursor == "base-cursor")
        let taskPayload = try #require(request.operations.compactMap(\.taskPayload).first)
        let recurringTaskPayload = try #require(request.operations.compactMap(\.recurringTaskPayload).first)
        #expect(taskPayload.basePrice == 320)
        #expect(recurringTaskPayload.basePrice == 90)
        #expect(recurringTaskPayload.minDailyFrequency == 4.0)
        let rewardPayload = try #require(request.operations.compactMap(\.rewardPayload).first)
        #expect(rewardPayload.basePrice == 1_000)
        #expect(rewardPayload.maxDailyFrequency == 0.25)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: local edits identify the server revision they were based on
    // so another device's accepted edit cannot be overwritten silently.
    @Test func dirtyTaskOperationKeepsOriginalBaseRevisionAcrossRemotePull() async throws {
        let taskID = RecordID("revision-task")
        let initialPull = makeResponse(
            tasks: [
                makeTaskRecord(id: taskID.rawValue, name: "Server task", serverRevision: 3)
            ],
            serverCursor: "3"
        )
        let remoteChange = makeResponse(
            tasks: [
                makeTaskRecord(id: taskID.rawValue, name: "Other device task", serverRevision: 4)
            ],
            serverCursor: "4"
        )
        let context = try await makeContext(pullResponse: initialPull)

        context.syncManager.updateSession(userID: userID)
        await context.syncManager.syncNow()
        context.taskStore.updateTask(id: taskID, name: "Local dirty task")
        context.syncAPIClient.pullHandler = { _, _ in remoteChange }

        await context.syncManager.syncNow()

        let operation = try #require(context.syncAPIClient.pushCalls.last?.0.operations.first)
        #expect(operation.baseRecordRevision == 3)
        #expect(operation.taskPayload?.name == "Local dirty task")

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: dirty local edits survive a full pull even when the server row
    // has a newer updatedAt, so a rejected push can retry the user's edit.
    @Test func fullPullDoesNotOverwriteDirtyTaskWhenPushFails() async throws {
        let taskID = RecordID("dirty-full-sync-task")
        let localTime = try #require(AppDateCoding.parseBackendTimestamp("2026-04-18T12:00:00.000000"))
        let remoteChange = makeResponse(
            tasks: [
                makeTaskRecord(
                    id: taskID.rawValue,
                    name: "Other device task",
                    updatedAt: "2026-04-18T13:00:00.000000",
                    serverRevision: 4
                )
            ],
            serverCursor: "4"
        )
        let context = try await makeContext(
            pullHandler: { _, _ in remoteChange },
            pushHandler: { _, _ in throw TestFailure.pushRejected }
        )

        context.syncManager.updateSession(userID: userID)
        _ = context.taskStore.addTask(
            id: taskID,
            name: "Local dirty task",
            basePrice: 240,
            createdAt: localTime,
            updatedAt: localTime
        )

        await context.syncManager.syncNow()

        let task = try #require(context.taskStore.tasks.first(where: { $0.id == taskID }))
        #expect(task.name == "Local dirty task")
        #expect(context.syncStateStore.state(for: userID).dirty.tasks.count == 1)
        #expect(context.syncStateStore.state(for: userID).lastSyncCursor == nil)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: non-task dirty records also carry the server revision they were
    // based on so the backend can reject stale writes instead of last-write-wins.
    @Test func dirtyRewardPushesAsOperationWithBaseRevision() async throws {
        let rewardID = RecordID("revision-reward")
        let initialPull = makeResponse(
            rewards: [
                makeRewardRecord(id: rewardID.rawValue, name: "Server reward", serverRevision: 7)
            ],
            serverCursor: "7"
        )
        let context = try await makeContext(pullResponse: initialPull)

        context.syncManager.updateSession(userID: userID)
        await context.syncManager.syncNow()
        context.rewardStore.updateReward(id: rewardID, name: "Local dirty reward")

        await context.syncManager.syncNow()

        let operation = try #require(context.syncAPIClient.pushCalls.last?.0.operations.first {
            $0.kind == "upsertReward"
        })
        #expect(operation.baseRecordRevision == 7)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: a successful push echo is authoritative even when the device
    // clock made the local updatedAt look newer than the server timestamp.
    @Test func pushEchoReplacesClockSkewedLocalTask() async throws {
        let taskID = RecordID("clock-skew-task")
        let skewedLocalTime = Date(timeIntervalSince1970: 4_102_444_800)
        let pullResponse = makeResponse(serverCursor: "base-cursor")
        let pushResponse = makeResponse(
            tasks: [
                makeTaskRecord(
                    id: taskID.rawValue,
                    name: "Server accepted task",
                    basePrice: 555,
                    updatedAt: "2026-04-18T12:00:00.000000"
                )
            ],
            serverCursor: "revision-2"
        )
        let context = try await makeContext(pullResponse: pullResponse, pushResponse: pushResponse)

        context.syncManager.updateSession(userID: userID)
        _ = context.taskStore.addTask(
            id: taskID,
            name: "Clock skew local task",
            basePrice: 555,
            createdAt: skewedLocalTime,
            updatedAt: skewedLocalTime
        )

        await context.syncManager.syncNow()

        let syncedTask = try #require(context.taskStore.tasks.first(where: { $0.id == taskID }))
        #expect(syncedTask.name == "Server accepted task")
        #expect(syncedTask.updatedAt == AppDateCoding.parseBackendTimestamp("2026-04-18T12:00:00.000000"))
        #expect(context.syncStateStore.state(for: userID).dirty.tasks.isEmpty)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: edits made while the pull request is in flight should push in
    // the same sync and stop retrying once the server accepts them.
    @Test func editDuringPullPushesAndClearsDirtyState() async throws {
        let pullResponse = makeResponse(serverCursor: "pull-cursor")
        let pushResponse = makeResponse(serverCursor: "push-cursor")
        let context = try await makeContext(pullResponse: pullResponse, pushResponse: pushResponse)

        context.syncAPIClient.pullHandler = { _, _ in
            await MainActor.run {
                _ = context.taskStore.addTask(
                    id: RecordID("during-pull-task"),
                    name: "During Pull",
                    basePrice: 515
                )
            }
            return pullResponse
        }

        context.syncManager.updateSession(userID: userID)
        await context.syncManager.syncNow()

        let pushedTask = try #require(context.syncAPIClient.pushCalls.last?.0.operations.first?.taskPayload)
        #expect(pushedTask.id == "during-pull-task")
        #expect(pushedTask.basePrice == 515)
        #expect(context.syncStateStore.state(for: userID).dirty.tasks.isEmpty)
        #expect(context.syncStateStore.state(for: userID).lastSyncCursor == "push-cursor")

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: one-time rewards use the submitted price directly and do not send max-frequency pricing data.
    @Test func oneOffRewardsPushPriceWithoutFrequency() async throws {
        let context = try await makeContext(pullResponse: makeResponse())

        context.syncManager.updateSession(userID: userID)
        _ = context.rewardStore.addReward(recurring: false, name: "One-time Reward", basePrice: 625)

        await context.syncManager.syncNow()

        let pushedReward = try #require(context.syncAPIClient.pushCalls.last?.0.operations.compactMap(\.rewardPayload).first)
        #expect(!pushedReward.recurring)
        #expect(pushedReward.basePrice == 625)
        #expect(pushedReward.maxDailyFrequency == nil)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: a successfully synced timer deletion should stop retrying and
    // remove the local tombstone because the server has accepted the delete.
    @Test func pushedTimerDeletesClearDirtyStateAndPurgeTombstones() async throws {
        let context = try await makeContext(pullResponse: makeResponse(serverCursor: "timer-base-cursor"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        context.syncManager.updateSession(userID: userID)
        let timer = try #require(context.timerStore.addTimer(
            id: RecordID("timer-delete-1"),
            name: "Focus",
            intervals: [TimerInterval(name: "Focus", durationSeconds: 1_500)],
            now: now
        ))
        context.timerStore.deleteTimer(id: timer.id, deletedAt: now.addingTimeInterval(60))

        await context.syncManager.syncNow()

        let pushedTimer = try #require(context.syncAPIClient.pushCalls.last?.0.operations.compactMap(\.timerPayload).first)
        #expect(pushedTimer.id == "timer-delete-1")
        #expect(pushedTimer.deletedAt != nil)
        #expect(context.syncStateStore.state(for: userID).dirty.timers.isEmpty)
        #expect(context.timerStore.timers.isEmpty)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: server palette changes still sync now that general difficulty is gone.
    @Test func pullPersistsThemePalettes() async throws {
        let response = makeResponse(
            themePalettes: SyncThemePalettes(main: .mint, accent: .semantic)
        )
        let context = try await makeContext(pullResponse: response)

        context.syncManager.updateSession(userID: userID)
        await context.syncManager.syncNow()

        #expect(context.userSettingsStore.themePalettes.main == .mint)
        #expect(context.userSettingsStore.themePalettes.accent == .semantic)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: local theme changes use the same operation envelope as synced rows.
    @Test func dirtyThemePalettesPushAsOperation() async throws {
        let context = try await makeContext(pullResponse: makeResponse(serverCursor: "theme-base-cursor"))

        context.syncManager.updateSession(userID: userID)
        context.userSettingsStore.setThemePalettes(
            BochiThemePalettePreferences(main: .mint, accent: .palette(.jade))
        )

        await context.syncManager.syncNow()

        let operation = try #require(context.syncAPIClient.pushCalls.last?.0.operations.first {
            $0.kind == "updateThemePalettes"
        })
        let pushedPalettes = try #require(operation.payload.themePalettesPayload)
        #expect(operation.baseRecordRevision == nil)
        #expect(pushedPalettes.main == .mint)
        #expect(pushedPalettes.accent == .palette(.jade))

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: a failed push surfaces an error and leaves the dirty row/checkpoint for the next sync attempt.
    @Test func failedPushDoesNotClearDirtyStateOrAdvanceCheckpoint() async throws {
        let pullResponse = makeResponse(serverCursor: "pull-cursor")
        let context = try await makeContext(
            pullHandler: { _, _ in pullResponse },
            pushHandler: { _, _ in throw TestFailure.pushRejected }
        )

        context.syncManager.updateSession(userID: userID)
        _ = context.taskStore.addTask(name: "Unpushed Task", basePrice: 410)

        await context.syncManager.syncNow()

        #expect(context.syncManager.status == .error("Sync failed."))
        let state = context.syncStateStore.state(for: userID)
        #expect(state.lastSyncCursor == nil)
        #expect(state.dirty.tasks.count == 1)

        context.syncManager.updateSession(userID: nil)
    }
}
