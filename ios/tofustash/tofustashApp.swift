import SwiftUI

// @main is the app entry point — like ReactDOM.createRoot(...).render(<App />).
@main
struct tofustashApp: App {
    @Environment(\.scenePhase) private var scenePhase

    // @State is like useState, but for the component's own lifecycle.
    // AuthManager is marked @Observable, which works like a fine-grained
    // Zustand/Jotai store: SwiftUI tracks which properties each view reads
    // and only re-renders views that depend on the specific property that changed.
    // Unlike React, there's no need for selectors or memo — it's automatic.
    @State private var authManager: AuthManager

    // HabitStore follows the same pattern as AuthManager — an @Observable class
    // injected into the environment so all child views can access it via
    // @Environment(HabitStore.self). Like creating a second context provider.
    @State private var habitStore: HabitStore

    // TagStore follows the same pattern — a separate @Observable class for
    // managing tags and their associations with habits.
    @State private var tagStore: TagStore

    // TradeStore tracks habit completion records. The completion count feeds
    // into the reward formula's frequency multiplier.
    @State private var tradeStore: TradeStore

    // BalanceStore tracks the user's tofu currency balance.
    @State private var balanceStore: BalanceStore

    // RewardStore holds the spendable reward catalog.
    @State private var rewardStore: RewardStore

    // UserSettingsStore holds gameplay settings like general difficulty.
    @State private var userSettingsStore: UserSettingsStore
    @State private var listPreferencesStore: ListPreferencesStore
    @State private var syncManager: SyncManager

    init() {
        let tokenStorage: TokenStorage = AppRuntimeEnvironment.isUITesting
            ? InMemoryTokenStorage()
            : KeychainTokenStorage()
        let appleEntitlementClient: AppleEntitlementClient = AppRuntimeEnvironment.isUITesting
            ? StaticAppleEntitlementClient(entitlement: .inactive)
            : StoreKitAppleEntitlementClient()
        let authManager = AuthManager(
            apiClient: AppConfiguration.makeAuthAPIClient(),
            tokenStorage: tokenStorage,
            appleEntitlementClient: appleEntitlementClient
        )
        let habitStore = HabitStore()
        let tagStore = TagStore()
        let tradeStore = TradeStore()
        let balanceStore = BalanceStore()
        let rewardStore = RewardStore()
        let userSettingsStore = UserSettingsStore()
        let listPreferencesStore = ListPreferencesStore()
        let syncStateStore = SyncStateStore()
        let syncManager = SyncManager(
            apiClient: AppConfiguration.makeSyncAPIClient(),
            authManager: authManager,
            syncStateStore: syncStateStore,
            habitStore: habitStore,
            rewardStore: rewardStore,
            tradeStore: tradeStore,
            tagStore: tagStore,
            balanceStore: balanceStore,
            userSettingsStore: userSettingsStore,
            listPreferencesStore: listPreferencesStore
        )

        _authManager = State(initialValue: authManager)
        _habitStore = State(initialValue: habitStore)
        _tagStore = State(initialValue: tagStore)
        _tradeStore = State(initialValue: tradeStore)
        _balanceStore = State(initialValue: balanceStore)
        _rewardStore = State(initialValue: rewardStore)
        _userSettingsStore = State(initialValue: userSettingsStore)
        _listPreferencesStore = State(initialValue: listPreferencesStore)
        _syncManager = State(initialValue: syncManager)
    }

    // `body` is like the render function — SwiftUI calls it to get the view tree.
    var body: some Scene {
        // WindowGroup is roughly <StrictMode><App /></StrictMode> — the root container.
        WindowGroup {
            ContentView()
                // .environment() is React Context. This is like wrapping in
                // <AuthContext.Provider value={authManager}>. Child views
                // access it with @Environment, which is useContext().
                .environment(authManager)
                .environment(habitStore)
                .environment(tagStore)
                .environment(tradeStore)
                .environment(balanceStore)
                .environment(rewardStore)
                .environment(userSettingsStore)
                .environment(listPreferencesStore)
                .environment(syncManager)
                // .task is useEffect with an empty dep array — runs once on mount.
                // `await` is native here; no need for the async-function-inside-useEffect pattern.
                .task { await authManager.bootstrap() }
                .task(id: authManager.user?.id) {
                    syncManager.updateSession(userID: authManager.user?.id)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        syncManager.handleAppDidBecomeActive()
                    }
                }
        }
    }
}
