import Foundation
import Testing
@testable import tofustash

private final class MockSyncURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

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
        let authManager: AuthManager
        let syncManager: SyncManager
        let syncStateStore: SyncStateStore
        let taskStore: TaskStore
        let taskDependencyStore: TaskDependencyStore
        let habitStore: HabitStore
        let rewardStore: RewardStore
        let specialOfferStore: SpecialOfferStore
        let tradeStore: TradeStore
        let tagStore: TagStore
        let balanceStore: BalanceStore
        let userSettingsStore: UserSettingsStore
        let reminderStore: ReminderStore
        let listPreferencesStore: ListPreferencesStore
        let syncAPIClient: MockSyncAPIClient
    }

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
        let tokens = TestHelpers.makeTokens(userId: "user-123")

        authAPIClient.loginResult = .success(tokens)
        authAPIClient.currentAccountResult = .success(TestHelpers.makeCurrentAccount(email: "user@example.com"))

        let authManager = AuthManager(
            apiClient: authAPIClient,
            tokenStorage: tokenStorage,
            appleEntitlementClient: entitlementClient
        )
        try await authManager.login(email: "user@example.com", password: "password123")

        let storageURL = TestHelpers.makeTemporaryFileURL("sync-manager")
        let taskStore = TaskStore(storageURL: storageURL)
        let taskDependencyStore = TaskDependencyStore(storageURL: storageURL)
        let habitStore = HabitStore(storageURL: storageURL)
        let rewardStore = RewardStore(storageURL: storageURL)
        let specialOfferStore = SpecialOfferStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let tagStore = TagStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        let userSettingsStore = UserSettingsStore(storageURL: storageURL)
        let reminderStore = ReminderStore(
            storageURL: storageURL,
            taskStore: taskStore,
            habitStore: habitStore,
            notificationScheduler: NoOpReminderNotificationScheduler()
        )
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
            taskStore: taskStore,
            taskDependencyStore: taskDependencyStore,
            habitStore: habitStore,
            rewardStore: rewardStore,
            specialOfferStore: specialOfferStore,
            tradeStore: tradeStore,
            tagStore: tagStore,
            balanceStore: balanceStore,
            userSettingsStore: userSettingsStore,
            reminderStore: reminderStore,
            listPreferencesStore: listPreferencesStore,
            debounceDuration: .seconds(60),
            backgroundPullDuration: .seconds(60),
            fullSyncResetDuration: .seconds(60 * 60)
        )

        return TestContext(
            authManager: authManager,
            syncManager: syncManager,
            syncStateStore: syncStateStore,
            taskStore: taskStore,
            taskDependencyStore: taskDependencyStore,
            habitStore: habitStore,
            rewardStore: rewardStore,
            specialOfferStore: specialOfferStore,
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
        tasks: [SyncTaskRecord] = [],
        habits: [SyncHabitRecord] = [],
        trades: [SyncTradeRecord] = [],
        tags: [SyncTagRecord] = [],
        taskTags: [SyncTaskTagRecord] = [],
        taskTaskDependencies: [SyncTaskTaskDependencyRecord] = [],
        taskHabitDependencies: [SyncTaskHabitDependencyRecord] = [],
        habitTags: [SyncHabitTagRecord] = [],
        rewards: [SyncRewardRecord] = [],
        rewardTags: [SyncRewardTagRecord] = [],
        specialOffers: [SyncSpecialOfferRecord] = [],
        generalDifficulty: Double = 5.0
    ) -> SyncResponse {
        SyncResponse(
            tasks: tasks,
            habits: habits,
            trades: trades,
            tags: tags,
            taskTags: taskTags,
            taskTaskDependencies: taskTaskDependencies,
            taskHabitDependencies: taskHabitDependencies,
            habitTags: habitTags,
            rewards: rewards,
            rewardTags: rewardTags,
            specialOffers: specialOffers,
            balance: SyncBalanceRecord(tofuBalance: 0),
            serverCursor: "cursor-123",
            serverTime: "2026-04-18T12:00:00.000000",
            email: "user@example.com",
            isPremium: false,
            generalDifficulty: generalDifficulty
        )
    }

    // Behaviour: When a user signs in after creating local-only data, the first
    // authenticated sync pushes that local data to the backend instead of discarding it.
    @Test func signingInMigratesLocalHabitAndPushesIt() async throws {
        let context = try await makeContext(pullResponse: makeResponse())

        _ = context.habitStore.addHabit(name: "Offline Habit")

        context.syncManager.updateSession(userID: "user-123")
        await context.syncManager.syncNow()

        #expect(context.habitStore.currentOwnerID == "user-123")
        #expect(context.syncAPIClient.pushCalls.count == 1)
        #expect(context.syncAPIClient.pushCalls[0].0.habits?.first?.name == "Offline Habit")

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: when the backend sync payload includes special offers, the
    // current owner should see the same offer locally after the pull finishes.
    @Test func pullPersistsSpecialOffersForCurrentOwner() async throws {
        let response = makeResponse(
            specialOffers: [
                SyncSpecialOfferRecord(
                    id: "offer-1",
                    entityKind: .task,
                    entityId: "task-1",
                    modifierPercent: 40,
                    createdAt: "2030-04-18T12:00:00.000000",
                    updatedAt: "2030-04-18T12:00:00.000000",
                    deletedAt: nil,
                    expiresAt: "2030-04-19T12:00:00.000000"
                )
            ]
        )
        let context = try await makeContext(pullResponse: response)

        context.syncManager.updateSession(userID: "user-123")
        await context.syncManager.syncNow()

        #expect(context.specialOfferStore.activeOffer(for: .task, entityID: "task-1")?.modifierPercent == 40)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: If a dirty local habit has newer fields than the server copy,
    // sync snapshots the local habit before pull so the push preserves the user's edit.
    @Test func dirtyHabitSnapshotPreservesLocalDifficultyDuringSync() async throws {
        let habitID = RecordID("habit-123")
        let staleServerHabit = SyncHabitRecord(
            id: habitID.rawValue,
            name: "Habit",
            description: "",
            createdAt: "2026-04-18T10:00:00.000000",
            updatedAt: "2026-04-18T10:00:00.000000",
            deletedAt: nil,
            minDailyFrequency: nil,
            difficultyTier: nil,
            durationSeconds: nil,
            lockoutDurationSeconds: nil,
            benefit: nil
        )

        let context = try await makeContext(
            pullResponse: makeResponse(habits: [staleServerHabit]),
            pushResponse: makeResponse(habits: [staleServerHabit])
        )

        _ = context.habitStore.addHabit(
            id: habitID,
            name: "Habit",
            difficultyTier: HabitDifficultyTier.trivial,
            durationSeconds: 900,
            lockoutDurationSeconds: 3600,
            benefit: 4,
            createdAt: Date(timeIntervalSince1970: 1_713_433_200),
            updatedAt: Date(timeIntervalSince1970: 1_713_433_200)
        )

        context.syncManager.updateSession(userID: "user-123")
        await context.syncManager.syncNow()

        let pushedHabits = context.syncAPIClient.pushCalls.compactMap { $0.0.habits }.flatMap { $0 }
        #expect(pushedHabits.contains {
            $0.id == habitID.rawValue
                && $0.difficultyTier == HabitDifficultyTier.trivial
                && $0.durationSeconds == 900
                && $0.lockoutDurationSeconds == 3600
                && $0.benefit == 4
        })

        context.syncManager.updateSession(userID: String?.none)
    }

    // Behaviour: if the device adds a due date locally, sync should keep it by
    // round-tripping the saved value through the server's push response.
    @Test func dirtyTaskDueDateRoundTripsThroughPushEcho() async throws {
        let taskID = RecordID("task-123")
        let expectedDueDate = "2026-04-25T09:00:00"
        let initialTask = SyncTaskRecord(
            id: taskID.rawValue,
            name: "Submit report",
            description: "",
            createdAt: "2026-04-18T10:00:00.000000",
            updatedAt: "2026-04-18T10:00:00.000000",
            deletedAt: nil,
            completedAt: nil,
            difficultyTier: .light,
            durationSeconds: 600,
            commitment: 2,
            dueDate: nil
        )
        let pullResponse = makeResponse(tasks: [initialTask])
        let echoedTask = SyncTaskRecord(
            id: taskID.rawValue,
            name: "Submit report",
            description: "",
            createdAt: "2026-04-18T10:00:00.000000",
            updatedAt: "2026-04-18T12:00:00.000000",
            deletedAt: nil,
            completedAt: nil,
            difficultyTier: .light,
            durationSeconds: 600,
            commitment: 2,
            dueDate: expectedDueDate
        )
        let pushResponse = makeResponse(tasks: [echoedTask])

        let context = try await makeContext(
            pullHandler: { _, _ in pullResponse },
            pushHandler: { _, _ in pushResponse }
        )

        context.syncManager.updateSession(userID: "user-123")
        await context.syncManager.syncNow()

        context.taskStore.updateTask(
            id: taskID,
            dueDate: .some(AppDateCoding.parseBackendTimestamp(expectedDueDate))
        )

        await context.syncManager.syncNow()

        #expect(
            context.syncAPIClient.pushCalls.last?.0.tasks?.first?.dueDate
                == AppDateCoding.backendTimestamp(
                    from: try #require(AppDateCoding.parseBackendTimestamp(expectedDueDate))
                )
        )

        let syncedTask = try #require(context.taskStore.tasks.first(where: { $0.id == taskID }))
        #expect(syncedTask.dueDate == AppDateCoding.parseBackendTimestamp(expectedDueDate))

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: if an existing task is edited while a pull is already in
    // flight, the stale pull response must not wipe the new due date.
    @Test func editingExistingTaskDuringInFlightPullKeepsDueDateForNextSync() async throws {
        final class PullGate: @unchecked Sendable {
            var continuation: CheckedContinuation<Void, Never>?
        }

        let taskID = RecordID("task-123")
        let expectedDueDate = "2026-04-25T09:00:00.000000"
        let staleServerTask = SyncTaskRecord(
            id: taskID.rawValue,
            name: "Submit report",
            description: "",
            createdAt: "2026-04-18T10:00:00.000000",
            updatedAt: "2026-04-18T10:00:00.000000",
            deletedAt: nil,
            completedAt: nil,
            difficultyTier: .light,
            durationSeconds: 600,
            commitment: 2,
            dueDate: nil
        )

        let context = try await makeContext(
            pullResponse: makeResponse(tasks: [staleServerTask]),
            pushResponse: makeResponse(tasks: [staleServerTask])
        )

        context.syncManager.updateSession(userID: "user-123")
        await context.syncManager.syncNow()

        let gate = PullGate()
        context.syncAPIClient.pullHandler = { _, _ in
            await withCheckedContinuation { continuation in
                gate.continuation = continuation
            }
            return SyncResponse(
                tasks: [staleServerTask],
                habits: [],
                trades: [],
                tags: [],
                taskTags: [],
                taskTaskDependencies: [],
                taskHabitDependencies: [],
                habitTags: [],
                rewards: [],
                rewardTags: [],
                specialOffers: [],
                balance: SyncBalanceRecord(tofuBalance: 0),
                serverCursor: "cursor-456",
                serverTime: "2026-04-18T12:00:00.000000",
                email: "user@example.com",
                isPremium: false,
                generalDifficulty: 5.0
            )
        }
        context.syncAPIClient.pushHandler = { request, _ in
            let echoedTasks = await MainActor.run { request.tasks ?? [] }
            return SyncResponse(
                tasks: echoedTasks,
                habits: [],
                trades: [],
                tags: [],
                taskTags: [],
                taskTaskDependencies: [],
                taskHabitDependencies: [],
                habitTags: [],
                rewards: [],
                rewardTags: [],
                specialOffers: [],
                balance: SyncBalanceRecord(tofuBalance: 0),
                serverCursor: "cursor-789",
                serverTime: "2026-04-18T12:05:00.000000",
                email: "user@example.com",
                isPremium: false,
                generalDifficulty: 5.0
            )
        }

        let syncTask = Task { await context.syncManager.syncNow() }
        while gate.continuation == nil {
            await Task.yield()
        }

        context.taskStore.updateTask(
            id: taskID,
            dueDate: .some(AppDateCoding.parseBackendTimestamp(expectedDueDate))
        )
        #expect(context.taskStore.tasks.first(where: { $0.id == taskID })?.dueDate == AppDateCoding.parseBackendTimestamp(expectedDueDate))
        #expect(context.syncStateStore.state(for: "user-123").dirty.tasks.contains { $0.id == taskID })

        gate.continuation?.resume()
        gate.continuation = nil
        await syncTask.value

        let syncedTask = try #require(context.taskStore.tasks.first(where: { $0.id == taskID }))
        #expect(syncedTask.dueDate == AppDateCoding.parseBackendTimestamp(expectedDueDate))
        #expect(context.syncStateStore.state(for: "user-123").dirty.tasks.contains { $0.id == taskID })

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: If the device carries a saved habit filter for a tag that is no
    // longer present after sign-in, switching into the signed-in owner should
    // prune that stale tag id instead of keeping the list filtered invisibly.
    @Test func signingInPrunesStaleHabitFilterTags() async throws {
        let context = try await makeContext(pullResponse: makeResponse())
        let deletedTag = context.tagStore.addTag(name: "Deleted Locally")!

        context.listPreferencesStore.toggleHabitTag(deletedTag.id)
        context.tagStore.deleteTag(id: deletedTag.id, shouldNotifySync: false)

        context.syncManager.updateSession(userID: "user-123")

        #expect(context.listPreferencesStore.currentOwnerID == "user-123")
        #expect(context.listPreferencesStore.habitPreferences.selectedTagIDs.isEmpty)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: a full sync should be authoritative for persisted owner data.
    // If the server now returns only one tag for a habit, stale older local
    // habit-tag links must disappear instead of sticking around forever.
    @Test func fullSyncReplacesStaleHabitTagAssociations() async throws {
        let habitID = RecordID("habit-1")
        let fitnessTagID = RecordID("tag-fitness")
        let staleTagAID = RecordID("tag-old-a")
        let staleTagBID = RecordID("tag-old-b")

        let serverHabit = SyncHabitRecord(
            id: habitID.rawValue,
            name: "Stretch hamstrings",
            description: "",
            createdAt: "2026-04-18T10:00:00.000000",
            updatedAt: "2026-04-18T10:00:00.000000",
            deletedAt: nil,
            minDailyFrequency: 1,
            difficultyTier: .light,
            durationSeconds: nil,
            lockoutDurationSeconds: nil,
            benefit: nil
        )
        let serverFitnessTag = SyncTagRecord(
            id: fitnessTagID.rawValue,
            name: "Fitness",
            colorHex: "#22C55E",
            createdAt: "2026-04-18T10:00:00.000000",
            updatedAt: "2026-04-18T10:00:00.000000",
            deletedAt: nil
        )
        let serverHabitTag = SyncHabitTagRecord(
            habitId: habitID.rawValue,
            tagId: fitnessTagID.rawValue,
            createdAt: "2026-04-18T10:00:00.000000",
            updatedAt: "2026-04-18T10:00:00.000000",
            deletedAt: nil
        )

        let context = try await makeContext(
            pullResponse: makeResponse(
                habits: [serverHabit],
                tags: [serverFitnessTag],
                habitTags: [serverHabitTag]
            )
        )

        context.habitStore.setCurrentOwner("user-123")
        context.tagStore.setCurrentOwner("user-123")

        _ = context.habitStore.addHabit(
            id: habitID,
            name: "Stretch hamstrings",
            description: "",
            frequency: 1,
            difficultyTier: .light,
            createdAt: Date(timeIntervalSince1970: 1_713_433_200),
            updatedAt: Date(timeIntervalSince1970: 1_713_433_200),
            shouldNotifySync: false
        )
        _ = context.tagStore.addTag(
            id: fitnessTagID,
            name: "Fitness",
            colorHex: "#22C55E",
            createdAt: Date(timeIntervalSince1970: 1_713_433_200),
            updatedAt: Date(timeIntervalSince1970: 1_713_433_200),
            shouldNotifySync: false
        )
        _ = context.tagStore.addTag(
            id: staleTagAID,
            name: "Old A",
            colorHex: "#FF0000",
            createdAt: Date(timeIntervalSince1970: 1_713_433_200),
            updatedAt: Date(timeIntervalSince1970: 1_713_433_200),
            shouldNotifySync: false
        )
        _ = context.tagStore.addTag(
            id: staleTagBID,
            name: "Old B",
            colorHex: "#0000FF",
            createdAt: Date(timeIntervalSince1970: 1_713_433_200),
            updatedAt: Date(timeIntervalSince1970: 1_713_433_200),
            shouldNotifySync: false
        )
        context.tagStore.addTagToHabit(tagId: fitnessTagID, habitId: habitID, shouldNotifySync: false)
        context.tagStore.addTagToHabit(tagId: staleTagAID, habitId: habitID, shouldNotifySync: false)
        context.tagStore.addTagToHabit(tagId: staleTagBID, habitId: habitID, shouldNotifySync: false)

        #expect(context.tagStore.tagsForHabit(habitId: habitID).count == 3)

        context.syncManager.updateSession(userID: "user-123")
        await context.syncManager.syncNow()

        let resultingTags = context.tagStore.tagsForHabit(habitId: habitID)
        #expect(resultingTags.count == 1)
        #expect(resultingTags.first?.id == fitnessTagID)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: first authenticated sync must preserve unsynced local-first
    // records even if the push response does not echo them back. The client
    // should rebuild from the server snapshot, reapply dirty local records, and
    // only then push.
    @Test func fullSyncPreservesDirtyLocalHabitWhenPushResponseIsEmpty() async throws {
        let localHabitID = RecordID("local-habit-1")

        let context = try await makeContext(
            pullResponse: makeResponse(),
            pushResponse: makeResponse()
        )

        _ = context.habitStore.addHabit(
            id: localHabitID,
            name: "Offline Habit",
            description: "",
            frequency: 1,
            difficultyTier: .light,
            createdAt: Date(timeIntervalSince1970: 1_713_433_200),
            updatedAt: Date(timeIntervalSince1970: 1_713_433_200)
        )

        context.syncManager.updateSession(userID: "user-123")
        await context.syncManager.syncNow()

        #expect(context.habitStore.activeHabits.contains { $0.id == localHabitID })
        #expect(context.syncAPIClient.pushCalls.count == 1)
        #expect(context.syncAPIClient.pushCalls[0].0.habits?.contains { $0.id == localHabitID.rawValue } == true)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: a dirty local general difficulty change must not be overwritten
    // by the pull phase before push runs. The local value should be pushed and
    // then remain persisted after sync completes.
    @Test func syncPreservesDirtyGeneralDifficultyUntilPush() async throws {
        let context = try await makeContext(
            pullResponse: makeResponse(generalDifficulty: 5.0),
            pushResponse: makeResponse(generalDifficulty: 10.0)
        )

        context.syncManager.updateSession(userID: "user-123")
        context.userSettingsStore.setGeneralDifficulty(10.0)
        await context.syncManager.syncNow()

        #expect(context.syncAPIClient.pushCalls.count == 1)
        #expect(context.syncAPIClient.pushCalls[0].0.generalDifficulty == 10.0)
        #expect(context.userSettingsStore.generalDifficulty == 10.0)

        context.syncManager.updateSession(userID: nil)
    }

    // Behaviour: if the user edits the same record again while a sync is in
    // flight, the newer local edit must survive the in-flight sync result.
    @Test func syncingSameHabitTwiceKeepsNewerEditLocallyApplied() async throws {
        final class PullGate: @unchecked Sendable {
            var continuation: CheckedContinuation<Void, Never>?
        }

        let gate = PullGate()
        let context = try await makeContext(
            pullHandler: { _, _ in
                await withCheckedContinuation { continuation in
                    gate.continuation = continuation
                }
                return await makeResponse()
            },
            pushHandler: { request, _ in
                await makeResponse(habits: request.habits ?? [])
            }
        )

        context.syncManager.updateSession(userID: "user-123")
        gate.continuation?.resume()
        gate.continuation = nil

        let created = try #require(context.habitStore.addHabit(name: "Original"))
        context.habitStore.updateHabit(id: created.id, name: "First Edit")

        let firstSync = Task { await context.syncManager.syncNow() }
        while gate.continuation == nil {
            await Task.yield()
        }

        context.habitStore.updateHabit(id: created.id, name: "Second Edit")
        gate.continuation?.resume()
        gate.continuation = nil
        await firstSync.value

        let updatedHabit = try #require(context.habitStore.activeHabits.first { $0.id == created.id })
        #expect(updatedHabit.name == "Second Edit")

        context.syncManager.updateSession(userID: nil)
    }
}

@MainActor
struct LiveSyncAPIClientTests {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockSyncURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeSyncResponseData() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "tasks": [],
                "habits": [],
                "trades": [],
                "tags": [],
                "taskTags": [],
                "taskTaskDependencies": [],
                "taskHabitDependencies": [],
                "habitTags": [],
                "rewards": [],
                "rewardTags": [],
                "specialOffers": [],
                "balance": ["tofuBalance": 0],
                "serverCursor": "cursor-123",
                "serverTime": "2026-04-18T12:00:00.000000",
                "email": NSNull(),
                "isPremium": false,
                "generalDifficulty": 5.0
            ]
        )
    }

    // Behaviour: when the app pulls sync data, the live HTTP client must target
    // the versioned sync endpoint so the installed build stays on its contract.
    @Test func pullSyncUsesVersionedEndpoint() async throws {
        let session = makeSession()
        let client = LiveSyncAPIClient(
            baseURL: try #require(URL(string: "https://example.com")),
            session: session
        )
        let responseData = try makeSyncResponseData()

        MockSyncURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/api/v1/sync")
            #expect(request.url?.query == "cursor=cursor-123")
            #expect(request.httpMethod == "GET")
            let url = try #require(request.url)

            return (
                try #require(
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )
                ),
                responseData
            )
        }
        defer { MockSyncURLProtocol.requestHandler = nil }

        let response = try await client.pullSync(cursor: "cursor-123", accessToken: "token-123")

        #expect(response.serverCursor == "cursor-123")
    }

    // Behaviour: when the app pushes local changes, the live HTTP client must
    // post them to the same versioned sync contract as pull.
    @Test func pushSyncUsesVersionedEndpoint() async throws {
        let session = makeSession()
        let client = LiveSyncAPIClient(
            baseURL: try #require(URL(string: "https://example.com")),
            session: session
        )
        let responseData = try makeSyncResponseData()

        MockSyncURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/api/v1/sync")
            #expect(request.httpMethod == "POST")
            let url = try #require(request.url)

            return (
                try #require(
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )
                ),
                responseData
            )
        }
        defer { MockSyncURLProtocol.requestHandler = nil }

        let response = try await client.pushSync(
            SyncPushRequest(
                tasks: nil,
                habits: nil,
                trades: nil,
                tags: nil,
                taskTags: nil,
                taskTaskDependencies: nil,
                taskHabitDependencies: nil,
                habitTags: nil,
                rewards: nil,
                rewardTags: nil,
                generalDifficulty: nil
            ),
            accessToken: "token-123"
        )

        #expect(response.serverCursor == "cursor-123")
    }
}
