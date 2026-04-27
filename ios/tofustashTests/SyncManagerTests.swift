import Foundation
import Testing
@testable import tofustash

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
        let habitStore: HabitStore
        let rewardStore: RewardStore
        let tradeStore: TradeStore
        let tagStore: TagStore
        let balanceStore: BalanceStore
        let userSettingsStore: UserSettingsStore
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
        let habitStore = HabitStore(storageURL: storageURL)
        let rewardStore = RewardStore(storageURL: storageURL)
        let tradeStore = TradeStore(storageURL: storageURL)
        let tagStore = TagStore(storageURL: storageURL)
        let balanceStore = BalanceStore(storageURL: storageURL)
        let userSettingsStore = UserSettingsStore(storageURL: storageURL)
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
            habitStore: habitStore,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            tagStore: tagStore,
            balanceStore: balanceStore,
            userSettingsStore: userSettingsStore,
            listPreferencesStore: listPreferencesStore,
            debounceDuration: .seconds(60),
            backgroundPullDuration: .seconds(60),
            fullSyncResetDuration: .seconds(60 * 60)
        )

        return TestContext(
            authManager: authManager,
            syncManager: syncManager,
            habitStore: habitStore,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            tagStore: tagStore,
            balanceStore: balanceStore,
            userSettingsStore: userSettingsStore,
            listPreferencesStore: listPreferencesStore,
            syncAPIClient: syncAPIClient
        )
    }

    private func makeResponse(
        habits: [SyncHabitRecord] = [],
        trades: [SyncTradeRecord] = [],
        tags: [SyncTagRecord] = [],
        habitTags: [SyncHabitTagRecord] = [],
        rewards: [SyncRewardRecord] = [],
        rewardTags: [SyncRewardTagRecord] = [],
        generalDifficulty: Double = 5.0
    ) -> SyncResponse {
        SyncResponse(
            habits: habits,
            trades: trades,
            tags: tags,
            habitTags: habitTags,
            rewards: rewards,
            rewardTags: rewardTags,
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
            skipConsequence: nil
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
            skipConsequence: 4,
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
                && $0.skipConsequence == 4
        })

        context.syncManager.updateSession(userID: String?.none)
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
            skipConsequence: nil
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
