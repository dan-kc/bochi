import SwiftUI
import UserNotifications

// Sync flow: constructs one shared SyncManager and attaches lifecycle modifiers
// that turn auth, edits, timers, and app activation into sync effects.
@main
struct bochiApp: App {
    @Environment(\.scenePhase) private var scenePhase

    // @State is like useState, but for the component's own lifecycle.
    // AuthManager is marked @Observable, which works like a fine-grained
    // Zustand/Jotai store: SwiftUI tracks which properties each view reads
    // and only re-renders views that depend on the specific property that changed.
    // Unlike React, there's no need for selectors or memo — it's automatic.
    @State private var authManager: AuthManager
    @State private var timerStore: TimerStore

    // RecurringTaskStore follows the same pattern as AuthManager — an @Observable class
    // injected into the environment so all child views can access it via
    // @Environment(RecurringTaskStore.self). Like creating a second context provider.
    @State private var taskStore: TaskStore
    @State private var taskDependencyStore: TaskDependencyStore
    @State private var recurringTaskStore: RecurringTaskStore

    // TagStore follows the same pattern — a separate @Observable class for
    // managing tags and their associations with recurringTasks.
    @State private var tagStore: TagStore

    // TradeStore tracks recurringTask completion records. The completion count feeds
    // into the reward formula's frequency multiplier.
    @State private var tradeStore: TradeStore

    // BalanceStore tracks the user's points currency balance.
    @State private var balanceStore: BalanceStore

    // RewardStore holds the spendable reward catalog.
    @State private var rewardStore: RewardStore
    @State private var rewardDependencyStore: RewardDependencyStore

    // UserSettingsStore holds app preferences.
    @State private var userSettingsStore: UserSettingsStore
    @State private var reminderStore: ReminderStore
    @State private var reminderNotificationReconciler: ReminderNotificationReconciler
    @State private var appNavigationStore: AppNavigationStore
    @State private var omniSearchStore: OmniSearchStore
    @State private var listPreferencesStore: ListPreferencesStore
    @State private var syncManager: SyncManager
    @State private var premiumAccessStore: PremiumAccessStore
    @State private var premiumWelcomeStore: PremiumWelcomeStore
    @State private var foregroundNotificationPresenter: ForegroundNotificationPresenter
    private let notificationRouteStore: NotificationTaskRouteStore

    init() {
        let authAPIClient: AuthAPIClient = AppConfiguration.makeAuthAPIClient()
        let tokenStorage: TokenStorage = KeychainTokenStorage()
        let appleEntitlementClient: AppleEntitlementClient = StoreKitAppleEntitlementClient()
        let authManager = AuthManager(
            apiClient: authAPIClient,
            tokenStorage: tokenStorage,
            appleEntitlementClient: appleEntitlementClient
        )
        let timerStore = TimerStore()
        let taskStore = TaskStore()
        let taskDependencyStore = TaskDependencyStore()
        let recurringTaskStore = RecurringTaskStore()
        let tagStore = TagStore()
        let tradeStore = TradeStore()
        let balanceStore = BalanceStore()
        let rewardStore = RewardStore()
        let rewardDependencyStore = RewardDependencyStore()
        let userSettingsStore = UserSettingsStore()
        let appNavigationStore = AppNavigationStore()
        let omniSearchStore = OmniSearchStore()
        let reminderScheduler: ReminderNotificationScheduling = LiveReminderNotificationScheduler()
        let reminderStore = ReminderStore()
        let reminderNotificationReconciler = ReminderNotificationReconciler(
            reminderStore: reminderStore,
            taskStore: taskStore,
            recurringTaskStore: recurringTaskStore,
            tradeStore: tradeStore,
            notificationScheduler: reminderScheduler
        )
        let notificationRouteStore = NotificationTaskRouteStore()
        let listPreferencesStore = ListPreferencesStore()
        let premiumAccessStore = PremiumAccessStore()
        let premiumWelcomeStore = PremiumWelcomeStore()
        let syncStateStore = SyncStateStore()
        let foregroundNotificationPresenter = ForegroundNotificationPresenter(
            routeStore: notificationRouteStore
        )
        let syncAPIClient: SyncAPIClient = AppConfiguration.makeSyncAPIClient()

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
        UNUserNotificationCenter.current().delegate = foregroundNotificationPresenter

        _authManager = State(initialValue: authManager)
        _timerStore = State(initialValue: timerStore)
        _taskStore = State(initialValue: taskStore)
        _taskDependencyStore = State(initialValue: taskDependencyStore)
        _recurringTaskStore = State(initialValue: recurringTaskStore)
        _tagStore = State(initialValue: tagStore)
        _tradeStore = State(initialValue: tradeStore)
        _balanceStore = State(initialValue: balanceStore)
        _rewardStore = State(initialValue: rewardStore)
        _rewardDependencyStore = State(initialValue: rewardDependencyStore)
        _userSettingsStore = State(initialValue: userSettingsStore)
        _reminderStore = State(initialValue: reminderStore)
        _reminderNotificationReconciler = State(initialValue: reminderNotificationReconciler)
        _appNavigationStore = State(initialValue: appNavigationStore)
        _omniSearchStore = State(initialValue: omniSearchStore)
        _listPreferencesStore = State(initialValue: listPreferencesStore)
        _syncManager = State(initialValue: syncManager)
        _premiumAccessStore = State(initialValue: premiumAccessStore)
        _premiumWelcomeStore = State(initialValue: premiumWelcomeStore)
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
                .environment(timerStore)
                .environment(taskStore)
                .environment(taskDependencyStore)
                .environment(recurringTaskStore)
                .environment(tagStore)
                .environment(tradeStore)
                .environment(balanceStore)
                .environment(rewardStore)
                .environment(rewardDependencyStore)
                .environment(userSettingsStore)
                .environment(reminderStore)
                .environment(appNavigationStore)
                .environment(omniSearchStore)
                .environment(listPreferencesStore)
                .environment(syncManager)
                .environment(premiumAccessStore)
                .environment(premiumWelcomeStore)
                .authSessionLifecycle(
                    authManager: authManager,
                    syncManager: syncManager
                )
                .accountDeletionLifecycle(
                    authManager: authManager,
                    dataCleaner: syncManager,
                    notificationCanceller: reminderNotificationReconciler
                )
                .appleTransactionLifecycle(authManager: authManager)
                .syncSessionLifecycle(
                    session: syncManager.syncSession,
                    syncManager: syncManager
                )
                .syncMutationLifecycle(
                    ownerID: syncManager.syncSession.ownerID,
                    syncManager: syncManager
                )
                .syncBackgroundPullLifecycle(
                    ownerID: syncManager.syncSession.ownerID,
                    syncManager: syncManager
                )
                .syncFullSyncResetLifecycle(
                    ownerID: syncManager.syncSession.ownerID,
                    syncManager: syncManager
                )
                .reminderNotificationLifecycle(
                    reminderStore: reminderStore,
                    notificationReconciler: reminderNotificationReconciler,
                    hasPremiumAccess: premiumAccessStore.hasPremiumAccess(authManager: authManager),
                    scenePhase: scenePhase
                )
                .notificationRouteLifecycle(
                    routeStore: notificationRouteStore,
                    appNavigationStore: appNavigationStore,
                    scenePhase: scenePhase
                )
                .appActivationLifecycle(
                    scenePhase: scenePhase,
                    ownerID: syncManager.syncSession.ownerID,
                    syncManager: syncManager,
                    tradeStore: tradeStore
                )
        }
    }
}
