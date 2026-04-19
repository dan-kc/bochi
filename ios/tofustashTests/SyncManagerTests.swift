import Foundation
import Testing
@testable import tofustash

@MainActor
struct SyncManagerTests {
    private final class MockSyncAPIClient: SyncAPIClient, @unchecked Sendable {
        var pullHandler: @Sendable (Date?, String) async throws -> SyncResponse
        var pushHandler: @Sendable (SyncPushRequest, String) async throws -> SyncResponse

        private(set) var pullCalls: [(Date?, String)] = []
        private(set) var pushCalls: [(SyncPushRequest, String)] = []

        init(
            pullHandler: @escaping @Sendable (Date?, String) async throws -> SyncResponse,
            pushHandler: @escaping @Sendable (SyncPushRequest, String) async throws -> SyncResponse
        ) {
            self.pullHandler = pullHandler
            self.pushHandler = pushHandler
        }

        func pullSync(since: Date?, accessToken: String) async throws -> SyncResponse {
            pullCalls.append((since, accessToken))
            return try await pullHandler(since, accessToken)
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

        let habitStore = HabitStore(storageURL: TestHelpers.makeTemporaryFileURL("habits"))
        let rewardStore = RewardStore(storageURL: TestHelpers.makeTemporaryFileURL("rewards"))
        let tradeStore = TradeStore(storageURL: TestHelpers.makeTemporaryFileURL("trades"))
        let tagStore = TagStore(storageURL: TestHelpers.makeTemporaryFileURL("tags"))
        let balanceStore = BalanceStore(storageURL: TestHelpers.makeTemporaryFileURL("balances"))
        let userSettingsStore = UserSettingsStore(storageURL: TestHelpers.makeTemporaryFileURL("settings"))
        let listPreferencesStore = ListPreferencesStore(storageURL: TestHelpers.makeTemporaryFileURL("list-preferences"))
        let syncStateStore = SyncStateStore(storageURL: TestHelpers.makeTemporaryFileURL("sync-state"))

        let syncAPIClient = MockSyncAPIClient(
            pullHandler: { _, _ in pullResponse },
            pushHandler: { request, _ in pushResponse ?? pullResponse }
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
            difficultyTier: nil
        )

        let context = try await makeContext(
            pullResponse: makeResponse(habits: [staleServerHabit]),
            pushResponse: makeResponse(habits: [staleServerHabit])
        )

        _ = context.habitStore.addHabit(
            id: habitID,
            name: "Habit",
            difficultyTier: HabitDifficultyTier.trivial,
            createdAt: Date(timeIntervalSince1970: 1_713_433_200),
            updatedAt: Date(timeIntervalSince1970: 1_713_433_200)
        )

        context.syncManager.updateSession(userID: "user-123")
        await context.syncManager.syncNow()

        let pushedHabits = context.syncAPIClient.pushCalls.compactMap { $0.0.habits }.flatMap { $0 }
        #expect(pushedHabits.contains { $0.id == habitID.rawValue && $0.difficultyTier == HabitDifficultyTier.trivial })

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
}
