import SwiftUI

// @main is the app entry point — like ReactDOM.createRoot(...).render(<App />).
@main
struct tofustashApp: App {
    // @State is like useState, but for the component's own lifecycle.
    // AuthManager is marked @Observable, which works like a fine-grained
    // Zustand/Jotai store: SwiftUI tracks which properties each view reads
    // and only re-renders views that depend on the specific property that changed.
    // Unlike React, there's no need for selectors or memo — it's automatic.
    @State private var authManager = AuthManager(
        apiClient: AppConfiguration.makeAuthAPIClient(),
        tokenStorage: KeychainTokenStorage()
    )

    // HabitStore follows the same pattern as AuthManager — an @Observable class
    // injected into the environment so all child views can access it via
    // @Environment(HabitStore.self). Like creating a second context provider.
    @State private var habitStore = HabitStore()

    // TagStore follows the same pattern — a separate @Observable class for
    // managing tags and their associations with habits.
    @State private var tagStore = TagStore()

    // TradeStore tracks habit completion records. The completion count feeds
    // into the reward formula's frequency multiplier.
    @State private var tradeStore = TradeStore()

    // BalanceStore tracks the user's tofu currency balance.
    @State private var balanceStore = BalanceStore()

    // RewardStore holds the spendable reward catalog.
    @State private var rewardStore = RewardStore()

    // UserSettingsStore holds gameplay settings like general difficulty.
    @State private var userSettingsStore = UserSettingsStore()

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
                // .task is useEffect with an empty dep array — runs once on mount.
                // `await` is native here; no need for the async-function-inside-useEffect pattern.
                .task { await authManager.bootstrap() }
        }
    }
}
