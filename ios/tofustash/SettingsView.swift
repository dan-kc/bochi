import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(SyncManager.self) private var syncManager
    @Environment(UserSettingsStore.self) private var userSettingsStore

    @State private var showingDifficulty = false
    @State private var restoreMessage: String?

    var body: some View {
        NavigationStack {
            List {
                gameplaySection
                syncSection

                if authManager.isLoading {
                    Section {
                        ProgressView("Loading account state…")
                    }
                } else {
                    accountSection
                }

                if let restoreMessage {
                    Section("Purchase Status") {
                        Text(restoreMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingDifficulty) {
                GeneralDifficultyView()
            }
        }
    }

    private var gameplaySection: some View {
        Section("Gameplay") {
            Button {
                showingDifficulty = true
            } label: {
                HStack {
                    Text("General Difficulty")
                    Spacer()
                    Text(String(format: "%g", userSettingsStore.generalDifficulty))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Label(syncManager.statusText, systemImage: syncManager.statusIconName)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(syncStatusColor)
            }

            if let lastSyncTime = syncManager.lastSyncTime {
                HStack {
                    Text("Last Sync")
                    Spacer()
                    Text(lastSyncTime.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .foregroundStyle(.secondary)
                }
            }

            if let lastErrorMessage = syncManager.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await syncManager.syncNow() }
            } label: {
                Label("Sync Now", systemImage: "arrow.clockwise")
            }
            .disabled(!authManager.canSync || syncManager.status == .syncing)
        } header: {
            Text("Sync")
        } footer: {
            if !authManager.canSync {
                Text("Create an account or sign in before sync can back up this device.")
            } else {
                Text("Changes are pushed after a short pause, remote updates are polled in the background, and a manual sync is available here.")
            }
        }
    }

    private var syncStatusColor: Color {
        switch syncManager.status {
        case .idle:
            return .secondary
        case .syncing:
            return .blue
        case .synced:
            return .green
        case .error:
            return .red
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        switch authManager.sessionState {
        case .signedOutFree:
            signedOutSection(
                title: "Local-Only Mode",
                systemImage: "iphone",
                detail: "Your habits stay on this device until you create an account. Sign in to sync and back up your progress."
            )
        case .signedOutPremiumRestored:
            signedOutSection(
                title: "Premium On This Device",
                systemImage: "crown",
                detail: "An Apple purchase is active on this device. Sign in or create an account to back it up and use it across devices."
            )
        case .signedInFree:
            signedInSection(
                title: "Free Account",
                systemImage: "person.crop.circle",
                detail: "This account can sync your data, but premium features are still locked."
            )
        case .signedInPremiumApple:
            signedInSection(
                title: "Premium via Apple",
                systemImage: "crown.fill",
                detail: premiumDetail(
                    fallback: "Premium is active through your Apple subscription."
                )
            )
        case .signedInPremiumWeb:
            signedInSection(
                title: "Premium via Account",
                systemImage: "sparkles",
                detail: premiumDetail(
                    fallback: "Premium is active through this account."
                )
            )
        case .signedInLapsed:
            signedInSection(
                title: "Premium Lapsed",
                systemImage: "clock.arrow.circlepath",
                detail: premiumDetail(
                    fallback: "Your account still syncs, but premium access is no longer active."
                )
            )
        }
    }

    private func signedOutSection(title: String, systemImage: String, detail: String) -> some View {
        Group {
            Section("Account") {
                Label(title, systemImage: systemImage)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                NavigationLink("Create Account") {
                    RegisterView()
                }

                NavigationLink("Log In") {
                    LoginView()
                }

                restorePurchaseButton
            }
        }
    }

    private func signedInSection(title: String, systemImage: String, detail: String) -> some View {
        Group {
            Section("Account") {
                if let user = authManager.user {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: systemImage)
                    }

                    if let expirationText = subscriptionExpirationText(for: user) {
                        Text(expirationText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                NavigationLink("Account Settings") {
                    AccountSettingsView()
                }
            }

            if authManager.hasUnlinkedAppleEntitlement {
                Section("Apple Purchase") {
                    Text("This device has an Apple premium entitlement, but it is not linked to this account yet. Premium sync features stay locked until the purchase is linked.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    restorePurchaseButton
                }
            } else if authManager.sessionState == .signedInFree || authManager.sessionState == .signedInLapsed {
                Section("Apple Purchase") {
                    restorePurchaseButton
                }
            }

            Section {
                Button("Log Out", role: .destructive) {
                    Task { await authManager.logout() }
                }
            }
        }
    }

    private var restorePurchaseButton: some View {
        Button {
            Task { await performRestore() }
        } label: {
            if authManager.isRestoringPurchases {
                Label("Restoring…", systemImage: "arrow.clockwise")
            } else {
                Label("Restore Apple Purchase", systemImage: "arrow.clockwise")
            }
        }
        .disabled(authManager.isRestoringPurchases)
    }

    private func performRestore() async {
        restoreMessage = nil

        do {
            try await authManager.restorePurchases()
            if authManager.sessionState == .signedOutPremiumRestored {
                restoreMessage = "Premium is now active on this device. Sign in to link it to an account later."
            } else if authManager.isPremiumEntitled {
                restoreMessage = "Premium access is active."
            } else if authManager.hasUnlinkedAppleEntitlement {
                restoreMessage = "An Apple premium entitlement exists on this device, but this account is not linked to it yet."
            } else {
                restoreMessage = "No active Apple purchases were found for this app."
            }
        } catch {
            if let apiError = error as? ApiError {
                restoreMessage = apiError.userFacingMessage
            } else {
                restoreMessage = "The App Store could not restore purchases right now. Please try again."
            }
        }
    }

    private func premiumDetail(fallback: String) -> String {
        guard let user = authManager.user else { return fallback }

        if let expirationText = subscriptionExpirationText(for: user) {
            return expirationText
        }

        return fallback
    }

    private func subscriptionExpirationText(for user: AuthUser) -> String? {
        guard let date = user.subscriptionExpiresAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        switch user.subscriptionStatus {
        case .active, .gracePeriod:
            return "Premium active until \(formatter.string(from: date))"
        case .billingRetry, .expired, .revoked:
            return "Premium ended on \(formatter.string(from: date))"
        case .none:
            return nil
        }
    }
}

#Preview {
    let previewAuthManager = AuthManager(
        apiClient: AppConfiguration.makeAuthAPIClient(),
        tokenStorage: KeychainTokenStorage(),
        appleEntitlementClient: StoreKitAppleEntitlementClient()
    )
    let previewTaskStore = TaskStore()
    let previewHabitStore = HabitStore()
    let previewSettingsStore = UserSettingsStore()
    let previewBalanceStore = BalanceStore()
    let previewReminderStore = ReminderStore(
        taskStore: previewTaskStore,
        habitStore: previewHabitStore,
        notificationScheduler: NoOpReminderNotificationScheduler()
    )
    let previewListPreferencesStore = ListPreferencesStore()

    SettingsView()
        .environment(previewAuthManager)
        .environment(previewSettingsStore)
        .environment(previewBalanceStore)
        .environment(previewListPreferencesStore)
        .environment(
            SyncManager(
                apiClient: AppConfiguration.makeSyncAPIClient(),
                authManager: previewAuthManager,
                syncStateStore: SyncStateStore(),
                taskStore: previewTaskStore,
                habitStore: previewHabitStore,
                rewardStore: RewardStore(),
                tradeStore: TradeStore(),
                tagStore: TagStore(),
                balanceStore: previewBalanceStore,
                userSettingsStore: previewSettingsStore,
                reminderStore: previewReminderStore,
                listPreferencesStore: previewListPreferencesStore
            )
        )
}
