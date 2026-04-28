import SwiftUI

// `struct ... : View` — a SwiftUI view. Think of it as a React FC. `View` is a protocol (like a TS interface / Rust trait).
struct ContentView: View {
    // `body` — the render method. `some View` is an opaque return type (like Rust's `impl View` — the compiler infers the concrete type)
    var body: some View {
        // SwiftUI uses declarative builder syntax — each nested block is like JSX children
        // ZStack layers the balance overlay on top of the TabView.
        // The overlay is rendered once and persists across tab switches —
        // no destroy/recreate cycle, so no re-render animations.
        // Like a fixed-position element in CSS above the router outlet.
        ZStack(alignment: .topTrailing) {
            TabView {
                Tab("Tasks", systemImage: "checkmark.square") {
                    TasksView()
                }
                Tab("Habits", systemImage: "checkmark.circle") {
                    HabitsView()
                }
                Tab("Rewards", systemImage: "gift") {
                    RewardsView()
                }
                Tab("Settings", systemImage: "gear") {
                    SettingsView()
                }
            }
            // `.modifier()` chaining — like wrapping a component: <SidebarAdaptable><TabView>...</TabView></SidebarAdaptable>
            .tabViewStyle(.sidebarAdaptable)

            // Balance display — top-right, above all tab content.
            BalanceOverlay()
                .padding(.trailing, 16)
                .padding(.top, 2)
        }
    }
}

// #Preview — Xcode live preview macro (like Storybook stories for components)
#Preview {
    let previewAuthManager = AuthManager(
        apiClient: AppConfiguration.makeAuthAPIClient(),
        tokenStorage: KeychainTokenStorage(),
        appleEntitlementClient: StoreKitAppleEntitlementClient()
    )
    let previewTaskStore = TaskStore()
    let previewHabitStore = HabitStore()
    let previewTagStore = TagStore()
    let previewTradeStore = TradeStore()
    let previewBalanceStore = BalanceStore()
    let previewRewardStore = RewardStore()
    let previewSettingsStore = UserSettingsStore()
    let previewListPreferencesStore = ListPreferencesStore()

    ContentView()
        // .environment() — injects into SwiftUI's environment (exactly like React Context Provider)
        .environment(previewAuthManager)
        .environment(previewTaskStore)
        .environment(previewHabitStore)
        .environment(previewTagStore)
        .environment(previewTradeStore)
        .environment(previewBalanceStore)
        .environment(previewRewardStore)
        .environment(previewSettingsStore)
        .environment(previewListPreferencesStore)
        .environment(
            SyncManager(
                apiClient: AppConfiguration.makeSyncAPIClient(),
                authManager: previewAuthManager,
                syncStateStore: SyncStateStore(),
                taskStore: previewTaskStore,
                habitStore: previewHabitStore,
                rewardStore: previewRewardStore,
                tradeStore: previewTradeStore,
                tagStore: previewTagStore,
                balanceStore: previewBalanceStore,
                userSettingsStore: previewSettingsStore,
                listPreferencesStore: previewListPreferencesStore
            )
        )
}
