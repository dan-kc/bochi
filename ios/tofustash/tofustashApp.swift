import SwiftUI
import UserNotifications

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
    @State private var taskStore: TaskStore
    @State private var taskDependencyStore: TaskDependencyStore
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
    @State private var specialOfferStore: SpecialOfferStore

    // UserSettingsStore holds gameplay settings like general difficulty.
    @State private var userSettingsStore: UserSettingsStore
    @State private var reminderStore: ReminderStore
    @State private var appNavigationStore: AppNavigationStore
    @State private var listPreferencesStore: ListPreferencesStore
    @State private var syncManager: SyncManager
    @State private var foregroundNotificationPresenter: ForegroundNotificationPresenter
    private let notificationRouteStore: NotificationTaskRouteStore

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
        let taskStore = TaskStore()
        let taskDependencyStore = TaskDependencyStore()
        let habitStore = HabitStore()
        let tagStore = TagStore()
        let tradeStore = TradeStore()
        let balanceStore = BalanceStore()
        let rewardStore = RewardStore()
        let specialOfferStore = SpecialOfferStore()
        let userSettingsStore = UserSettingsStore()
        let appNavigationStore = AppNavigationStore()
        let reminderScheduler: ReminderNotificationScheduling = AppRuntimeEnvironment.isUITesting
            ? NoOpReminderNotificationScheduler()
            : LiveReminderNotificationScheduler()
        let reminderStore = ReminderStore(
            taskStore: taskStore,
            habitStore: habitStore,
            notificationScheduler: reminderScheduler
        )
        let notificationRouteStore = NotificationTaskRouteStore()
        let listPreferencesStore = ListPreferencesStore()
        let syncStateStore = SyncStateStore()
        let foregroundNotificationPresenter = ForegroundNotificationPresenter(
            routeStore: notificationRouteStore
        )
        let syncManager = SyncManager(
            apiClient: AppConfiguration.makeSyncAPIClient(),
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
            listPreferencesStore: listPreferencesStore
        )
        UNUserNotificationCenter.current().delegate = foregroundNotificationPresenter

        _authManager = State(initialValue: authManager)
        _taskStore = State(initialValue: taskStore)
        _taskDependencyStore = State(initialValue: taskDependencyStore)
        _habitStore = State(initialValue: habitStore)
        _tagStore = State(initialValue: tagStore)
        _tradeStore = State(initialValue: tradeStore)
        _balanceStore = State(initialValue: balanceStore)
        _rewardStore = State(initialValue: rewardStore)
        _specialOfferStore = State(initialValue: specialOfferStore)
        _userSettingsStore = State(initialValue: userSettingsStore)
        _reminderStore = State(initialValue: reminderStore)
        _appNavigationStore = State(initialValue: appNavigationStore)
        _listPreferencesStore = State(initialValue: listPreferencesStore)
        _syncManager = State(initialValue: syncManager)
        _foregroundNotificationPresenter = State(initialValue: foregroundNotificationPresenter)
        self.notificationRouteStore = notificationRouteStore
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
                .environment(taskStore)
                .environment(taskDependencyStore)
                .environment(habitStore)
                .environment(tagStore)
                .environment(tradeStore)
                .environment(balanceStore)
                .environment(rewardStore)
                .environment(specialOfferStore)
                .environment(userSettingsStore)
                .environment(reminderStore)
                .environment(appNavigationStore)
                .environment(listPreferencesStore)
                .environment(syncManager)
                // .task is useEffect with an empty dep array — runs once on mount.
                // `await` is native here; no need for the async-function-inside-useEffect pattern.
                .task { await authManager.bootstrap() }
                .task(id: authManager.user?.id) {
                    syncManager.updateSession(userID: authManager.user?.id)
                }
                .onAppear {
                    guard scenePhase == .active else { return }
                    scheduleActivationWork()
                }
                .onReceive(NotificationCenter.default.publisher(for: .notificationEntityRouteDidChange)) { _ in
                    DispatchQueue.main.async {
                        activateQueuedNotificationNavigationIfNeeded()
                    }
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        scheduleActivationWork()
                    }
                }
        }
    }

    private func scheduleActivationWork() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            activateQueuedNotificationNavigationIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            syncManager.handleAppDidBecomeActive()
            reminderStore.reconcileNotifications()
        }
    }

    @MainActor
    private func activateQueuedNotificationNavigationIfNeeded() {
        guard let route = notificationRouteStore.consumeQueuedRoute() else { return }
        switch route {
        case .task(let taskID):
            appNavigationStore.openTaskForm(taskID: taskID)
        case .habit(let habitID):
            appNavigationStore.openHabitForm(habitID: habitID)
        }
    }
}
