import SwiftUI

// `struct ... : View` — a SwiftUI view. Think of it as a React FC. `View` is a protocol (like a TS interface / Rust trait).
struct ContentView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppNavigationStore.self) private var appNavigationStore
    @Environment(PremiumAccessStore.self) private var premiumAccessStore
    @Environment(PremiumWelcomeStore.self) private var premiumWelcomeStore
    @Environment(UserSettingsStore.self) private var userSettingsStore
    @Environment(OmniSearchStore.self) private var omniSearchStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(RecurringTaskStore.self) private var recurringTaskStore
    @Environment(RewardStore.self) private var rewardStore
    @Environment(TagStore.self) private var tagStore
    @Environment(ListPreferencesStore.self) private var listPreferencesStore
    @Namespace private var omniSearchNamespace

    private var themePalettes: BochiThemePalettePreferences {
        userSettingsStore.effectiveThemePalettes(
            hasPremiumAccess: premiumAccessStore.hasPremiumAccess(authManager: authManager)
        )
    }

    // `body` — the render method. `some View` is an opaque return type (like Rust's `impl View` — the compiler infers the concrete type)
    var body: some View {
        let theme = BochiTheme(palettes: themePalettes)

        ZStack {
            theme.appBackground()
                .ignoresSafeArea()

            TabView(selection: Binding(
                get: { appNavigationStore.selectedTab },
                set: selectTab
            )) {
                Tab("Earn", systemImage: "plus.circle", value: .earn) {
                    EarnView()
                }
                Tab("Spend", systemImage: "gift", value: .spend) {
                    SpendView()
                }
                Tab("Bank", systemImage: "lock.fill", value: .vault) {
                    VaultView()
                }
                Tab("Settings", systemImage: "gear", value: .settings) {
                    SettingsView()
                }
            }
            // `.modifier()` chaining — like wrapping a component: <SidebarAdaptable><TabView>...</TabView></SidebarAdaptable>
            .tabViewStyle(.sidebarAdaptable)
            // Behaviour: every tab keeps the same Radix gray surface behind
            // tab content and the tab bar in both light and dark mode.
            .background(theme.appBackground())
            .toolbarBackground(theme.appBackground(), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            // Behaviour: the active tab uses the palette configured for that
            // tab in the theme rather than one global system accent.
            .tint(theme.tabTint(for: appNavigationStore.selectedTab))
            // Behaviour: search is a modal overlay for assistive tech too, so
            // users should not tab into results and the covered list at once.
            .accessibilityHidden(omniSearchStore.isPresented)
        }
        .bochiTheme(theme)
        .background {
            // Behaviour: iOS reveals the host window around the keyboard's
            // rounded corners, so keep that backing surface in the app theme too.
            WindowBackgroundSetter(color: theme.appBackgroundUIColor())
        }
        .foregroundStyle(theme.primaryText())
        .environment(\.omniSearchNamespace, omniSearchNamespace)
        .overlay {
            // Behaviour: omni search covers the whole app surface while keeping
            // root-level overlays, especially balance, available above it.
            OmniSearchOverlay()
        }
        .overlay(alignment: .top) {
            RootEntityListControlsOverlay()
        }
        .overlay(alignment: .topTrailing) {
            // Balance display — top-right, above all tab content.
            BalanceOverlay()
                .padding(.trailing, 16)
                .padding(.top, 2)
        }
        .overlay {
            if appNavigationStore.isPresentingNewEntityForm {
                // Behaviour: taps outside the presented new-entity sheet should
                // behave like pressing Cancel, while the sheet decides whether
                // the current draft needs a discard confirmation.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appNavigationStore.requestNewEntityFormDismissAttempt()
                    }
                    .accessibilityHidden(true)
            }
        }
        .sheet(
            item: Binding(
                get: { appNavigationStore.newEntityFormRoute },
                set: { route in
                    if route == nil {
                        appNavigationStore.dismissNewEntityForm()
                    }
                }
            )
        ) { route in
            NewEntityFormView(
                initialSnapshot: route.snapshot,
                onTaskCreated: { task in
                    handleCreatedEntity(.task(task.id), originTab: route.originTab)
                },
                onRecurringTaskCreated: { recurringTask in
                    handleCreatedEntity(.recurringTask(recurringTask.id), originTab: route.originTab)
                },
                onRewardCreated: { reward in
                    handleCreatedEntity(.reward(reward.id), originTab: route.originTab)
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { premiumWelcomeStore.isPresented },
                set: { isPresented in
                    if !isPresented {
                        premiumWelcomeStore.dismiss()
                    }
                }
            )
        ) {
            PremiumWelcomeView()
        }
        .task(id: premiumWelcomeStore.presentationRequestID) {
            let requestID = premiumWelcomeStore.presentationRequestID
            guard requestID > 0 else { return }

            // Behaviour: a purchase usually completes inside a full-screen
            // StoreKit/upsell presentation. The root view waits for that stack
            // to settle before asking SwiftUI to present the welcome sheet.
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            premiumWelcomeStore.present(requestID: requestID)
        }
    }

    private func selectTab(_ selectedTab: AppTab) {
        withAnimation(.easeInOut(duration: 0.22)) {
            appNavigationStore.selectedTab = selectedTab
            appNavigationStore.resetRootEntityListControlsVisibility()
        }
    }

    private func handleCreatedEntity(_ route: PendingEntityFormRoute, originTab: AppTab) {
        if originTab == .earn && route.isEarnEntity {
            appNavigationStore.queueEntityReveal(route)
            return
        }

        if omniSearchStore.isPresented {
            guard omniSearchResultsContain(route) else { return }
            appNavigationStore.selectedTab = route.tab
            appNavigationStore.queueEntityReveal(route)
            return
        }

        if route.tab == originTab {
            appNavigationStore.queueEntityReveal(route)
            return
        }

        appNavigationStore.selectedTab = route.tab
    }

    private func omniSearchResultsContain(_ route: PendingEntityFormRoute) -> Bool {
        let snapshot = OmniSearchSupport.makeSnapshot(
            tasks: taskStore.tasks,
            recurringTasks: recurringTaskStore.recurringTasks,
            rewards: rewardStore.rewards,
            queryText: omniSearchStore.text
        )
        guard !snapshot.results.isEmpty else { return false }

        return snapshot.results.contains { result in
            switch (route, result) {
            case (.task(let routeID), .task(let task)):
                return routeID == task.id
            case (.recurringTask(let routeID), .recurringTask(let recurringTask)):
                return routeID == recurringTask.id
            case (.reward(let routeID), .reward(let reward)):
                return routeID == reward.id
            default:
                return false
            }
        }
    }
}

private extension PendingEntityFormRoute {
    var isEarnEntity: Bool {
        switch self {
        case .task, .recurringTask:
            return true
        case .reward:
            return false
        }
    }
}

private struct RootEntityListControlsConfiguration {
    let preferences: EntityListPreferences
    let tagScope: EntityListTagScope
    let availableTags: [Tag]
    let statusFilters: [EntityListStatusFilter]
    var showsSort: Bool = true
    let onSelectSort: (EntityListSortOption) -> Void
    let onToggleStatus: (EntityListStatusFilter) -> Void
    let onToggleTag: (RecordID) -> Void
    var onToggleTaskGroup: (() -> Void)? = nil
    var onToggleTaskCompletion: ((EntityListStatusFilter) -> Void)? = nil
}

private struct RootEntityListControlsOverlay: View {
    @Environment(AppNavigationStore.self) private var appNavigationStore
    @Environment(OmniSearchStore.self) private var omniSearchStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(RecurringTaskStore.self) private var recurringTaskStore
    @Environment(RewardStore.self) private var rewardStore
    @Environment(TagStore.self) private var tagStore
    @Environment(ListPreferencesStore.self) private var listPreferencesStore

    var body: some View {
        let selectedTab = appNavigationStore.selectedTab

        if let configuration = controlsConfiguration(selectedTab: selectedTab) {
            RootEntityListControlsVisibilityLayer(configuration: configuration)
        }
    }

    private func controlsConfiguration(selectedTab: AppTab) -> RootEntityListControlsConfiguration? {
        if omniSearchStore.isPresented {
            return searchControlsConfiguration()
        }

        guard showsRootEntityListControls(for: selectedTab) else { return nil }

        return rootEntityListControlsConfiguration(for: selectedTab)
    }

    private func showsRootEntityListControls(for selectedTab: AppTab) -> Bool {
        switch selectedTab {
        case .earn, .spend:
            return true
        case .tasks, .recurringTasks, .rewards:
            return false
        case .vault, .settings:
            return false
        }
    }

    private func rootEntityListControlsConfiguration(for selectedTab: AppTab) -> RootEntityListControlsConfiguration? {
        switch selectedTab {
        case .earn:
            guard taskStore.tasks.contains(where: { $0.deletedAt == nil }) || !recurringTaskStore.activeRecurringTasks.isEmpty else { return nil }
            return RootEntityListControlsConfiguration(
                preferences: listPreferencesStore.earnPreferences,
                tagScope: .earn,
                availableTags: tagStore.activeTags,
                statusFilters: [.task, .recurringTask, .hidden, .locked],
                onSelectSort: { option in
                    withAnimation(.default) {
                        listPreferencesStore.setEarnSort(option)
                    }
                },
                onToggleStatus: listPreferencesStore.toggleEarnStatus,
                onToggleTag: listPreferencesStore.toggleEarnTag,
                onToggleTaskGroup: listPreferencesStore.toggleEarnTaskGroup,
                onToggleTaskCompletion: listPreferencesStore.toggleEarnTaskCompletion
            )
        case .tasks:
            guard taskStore.tasks.contains(where: { $0.deletedAt == nil }) else { return nil }
            return RootEntityListControlsConfiguration(
                preferences: listPreferencesStore.taskPreferences,
                tagScope: .tasks,
                availableTags: tagStore.activeTags,
                statusFilters: [.incomplete, .completed, .hidden, .locked],
                onSelectSort: { option in
                    withAnimation(.default) {
                        listPreferencesStore.setTaskSort(option)
                    }
                },
                onToggleStatus: listPreferencesStore.toggleTaskStatus,
                onToggleTag: listPreferencesStore.toggleTaskTag
            )
        case .recurringTasks:
            guard !recurringTaskStore.activeRecurringTasks.isEmpty else { return nil }
            return RootEntityListControlsConfiguration(
                preferences: listPreferencesStore.recurringTaskPreferences,
                tagScope: .recurringTasks,
                availableTags: tagStore.activeTags,
                statusFilters: [.recurringTask, .hidden, .locked],
                onSelectSort: { option in
                    withAnimation(.default) {
                        listPreferencesStore.setRecurringTaskSort(option)
                    }
                },
                onToggleStatus: listPreferencesStore.toggleRecurringTaskStatus,
                onToggleTag: listPreferencesStore.toggleRecurringTaskTag
            )
        case .spend:
            guard !rewardStore.activeRewards.isEmpty else { return nil }
            return RootEntityListControlsConfiguration(
                preferences: listPreferencesStore.rewardPreferences,
                tagScope: .rewards,
                availableTags: tagStore.activeTags,
                statusFilters: [.recurringTask, .hidden, .locked],
                onSelectSort: { option in
                    withAnimation(.default) {
                        listPreferencesStore.setRewardSort(option)
                    }
                },
                onToggleStatus: listPreferencesStore.toggleRewardStatus,
                onToggleTag: listPreferencesStore.toggleRewardTag
            )
        case .rewards:
            return nil
        case .vault, .settings:
            return nil
        }
    }

    private func searchControlsConfiguration() -> RootEntityListControlsConfiguration {
        RootEntityListControlsConfiguration(
            preferences: omniSearchStore.preferences,
            tagScope: .search,
            availableTags: tagStore.activeTags,
            statusFilters: [.taskGroup, .reward, .task, .recurringTask, .completed, .hidden, .locked],
            showsSort: false,
            onSelectSort: { _ in },
            onToggleStatus: omniSearchStore.toggleStatus,
            onToggleTag: omniSearchStore.toggleTag
        )
    }
}

private struct RootEntityListControlsVisibilityLayer: View {
    @Environment(AppNavigationStore.self) private var appNavigationStore
    @Environment(OmniSearchStore.self) private var omniSearchStore

    let configuration: RootEntityListControlsConfiguration

    var body: some View {
        let controlsAreVisible = omniSearchStore.isPresented || appNavigationStore.rootEntityListControlsAreVisible

        EntityListControls(
            preferences: configuration.preferences,
            tagScope: configuration.tagScope,
            availableTags: configuration.availableTags,
            statusFilters: configuration.statusFilters,
            isEnabled: controlsAreVisible,
            showsSort: configuration.showsSort,
            onSelectSort: configuration.onSelectSort,
            onToggleStatus: configuration.onToggleStatus,
            onToggleTag: configuration.onToggleTag,
            onToggleTaskGroup: configuration.onToggleTaskGroup,
            onToggleTaskCompletion: configuration.onToggleTaskCompletion
        )
        .entityListRootControlsSurface(isVisible: controlsAreVisible)
    }
}

private enum EntityListRootControlsLayout {
    static let navigationTitleClearance: CGFloat = 44
    static let topPadding: CGFloat = 6
    static let bottomPadding: CGFloat = 10
    static let estimatedControlsHeight: CGFloat = 32
    static let hiddenExtraClearance = estimatedControlsHeight * 1.5
    static let hiddenYOffset = -(
        navigationTitleClearance
            + topPadding
            + bottomPadding
            + estimatedControlsHeight
            + hiddenExtraClearance
            + 12
    )
}

private extension View {
    func entityListRootControlsSurface(isVisible: Bool) -> some View {
        padding(.top, EntityListRootControlsLayout.topPadding)
            .padding(.bottom, EntityListRootControlsLayout.bottomPadding)
            .padding(.top, EntityListRootControlsLayout.navigationTitleClearance)
            // Behaviour: hiding is a physical move upward, so the controls pass
            // under the title and balance instead of fading or collapsing rows.
            .offset(y: isVisible ? 0 : EntityListRootControlsLayout.hiddenYOffset)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
            .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isVisible)
    }
}

private struct WindowBackgroundSetter: UIViewRepresentable {
    let color: UIColor

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        updateWindow(for: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        updateWindow(for: uiView)
    }

    private func updateWindow(for view: UIView) {
        DispatchQueue.main.async {
            view.window?.backgroundColor = color
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
    let previewTimerStore = TimerStore()
    let previewTaskStore = TaskStore()
    let previewTaskDependencyStore = TaskDependencyStore()
    let previewRecurringTaskStore = RecurringTaskStore()
    let previewTagStore = TagStore()
    let previewTradeStore = TradeStore()
    let previewBalanceStore = BalanceStore()
    let previewRewardStore = RewardStore()
    let previewRewardDependencyStore = RewardDependencyStore()
    let previewSettingsStore = UserSettingsStore()
    let previewReminderStore = ReminderStore()
    let previewNavigationStore = AppNavigationStore()
    let previewOmniSearchStore = OmniSearchStore()
    let previewListPreferencesStore = ListPreferencesStore()
    let previewPremiumAccessStore = PremiumAccessStore()
    let previewPremiumWelcomeStore = PremiumWelcomeStore()

    ContentView()
        // .environment() — injects into SwiftUI's environment (exactly like React Context Provider)
        .environment(previewAuthManager)
        .environment(previewTimerStore)
        .environment(previewTaskStore)
        .environment(previewTaskDependencyStore)
        .environment(previewRecurringTaskStore)
        .environment(previewTagStore)
        .environment(previewTradeStore)
        .environment(previewBalanceStore)
        .environment(previewRewardStore)
        .environment(previewRewardDependencyStore)
        .environment(previewSettingsStore)
        .environment(previewReminderStore)
        .environment(previewNavigationStore)
        .environment(previewOmniSearchStore)
        .environment(previewListPreferencesStore)
        .environment(previewPremiumAccessStore)
        .environment(previewPremiumWelcomeStore)
        .environment(
            SyncManager(
                apiClient: AppConfiguration.makeSyncAPIClient(),
                authManager: previewAuthManager,
                syncStateStore: SyncStateStore(),
                timerStore: previewTimerStore,
                taskStore: previewTaskStore,
                taskDependencyStore: previewTaskDependencyStore,
                rewardDependencyStore: previewRewardDependencyStore,
                recurringTaskStore: previewRecurringTaskStore,
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
