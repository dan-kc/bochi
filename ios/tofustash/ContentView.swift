import SwiftUI

// `struct ... : View` — a SwiftUI view. Think of it as a React FC. `View` is a protocol (like a TS interface / Rust trait).
struct ContentView: View {
    @Environment(AppNavigationStore.self) private var appNavigationStore

    // `body` — the render method. `some View` is an opaque return type (like Rust's `impl View` — the compiler infers the concrete type)
    var body: some View {
        // SwiftUI uses declarative builder syntax — each nested block is like JSX children
        // ZStack layers the balance overlay on top of the TabView.
        // The overlay is rendered once and persists across tab switches —
        // no destroy/recreate cycle, so no re-render animations.
        // Like a fixed-position element in CSS above the router outlet.
        ZStack(alignment: .topTrailing) {
            TabView(selection: Binding(
                get: { appNavigationStore.selectedTab },
                set: { appNavigationStore.selectedTab = $0 }
            )) {
                Tab("Tasks", systemImage: "checkmark.square", value: .tasks) {
                    TasksView()
                }
                Tab("Habits", systemImage: "checkmark.circle", value: .habits) {
                    HabitsView()
                }
                Tab("Rewards", systemImage: "gift", value: .rewards) {
                    RewardsView()
                }
                Tab("Settings", systemImage: "gear", value: .settings) {
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
    let previewTaskDependencyStore = TaskDependencyStore()
    let previewHabitStore = HabitStore()
    let previewTagStore = TagStore()
    let previewTradeStore = TradeStore()
    let previewBalanceStore = BalanceStore()
    let previewRewardStore = RewardStore()
    let previewSettingsStore = UserSettingsStore()
    let previewReminderStore = ReminderStore(
        taskStore: previewTaskStore,
        habitStore: previewHabitStore,
        notificationScheduler: NoOpReminderNotificationScheduler()
    )
    let previewNavigationStore = AppNavigationStore()
    let previewListPreferencesStore = ListPreferencesStore()

    ContentView()
        // .environment() — injects into SwiftUI's environment (exactly like React Context Provider)
        .environment(previewAuthManager)
        .environment(previewTaskStore)
        .environment(previewTaskDependencyStore)
        .environment(previewHabitStore)
        .environment(previewTagStore)
        .environment(previewTradeStore)
        .environment(previewBalanceStore)
        .environment(previewRewardStore)
        .environment(previewSettingsStore)
        .environment(previewReminderStore)
        .environment(previewNavigationStore)
        .environment(previewListPreferencesStore)
        .environment(
            SyncManager(
                apiClient: AppConfiguration.makeSyncAPIClient(),
                authManager: previewAuthManager,
                syncStateStore: SyncStateStore(),
                taskStore: previewTaskStore,
                taskDependencyStore: previewTaskDependencyStore,
                habitStore: previewHabitStore,
                rewardStore: previewRewardStore,
                tradeStore: previewTradeStore,
                tagStore: previewTagStore,
                balanceStore: previewBalanceStore,
                userSettingsStore: previewSettingsStore,
                reminderStore: previewReminderStore,
                listPreferencesStore: previewListPreferencesStore
            )
        )
}
