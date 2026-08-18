import SwiftUI

struct SettingsView: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(AuthManager.self) private var authManager
    @Environment(SyncManager.self) private var syncManager
    @Environment(UserSettingsStore.self) private var userSettingsStore
    @Environment(PremiumAccessStore.self) private var premiumAccessStore

    @State private var restoreMessage: String?
    @State private var authErrorMessage: String?
    @State private var accountDeletionErrorMessage: String?
    @State private var isSigningInWithApple = false
    @State private var isPremiumUpsellPresented = false
    @State private var isAccountDeletionSheetPresented = false
    @State private var accountDeletionFeedback = AccountDeletionFeedbackState()

    var body: some View {
        NavigationStack {
            List {
                gameplaySection
                entityRowsSection
                syncSection

                if authManager.isLoading {
                    Section {
                        ProgressView("Loading account state…")
                    }
                } else {
                    accountSection
                }
                premiumSection
                dangerZoneSection
                legalSection
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .foregroundStyle(theme.primaryText())
            .navigationTitle("Settings")
        }
        .background(theme.appBackground())
        .fullScreenCover(isPresented: $isPremiumUpsellPresented) {
            PremiumUpsellView()
        }
        .sheet(
            isPresented: $isAccountDeletionSheetPresented,
            onDismiss: { accountDeletionFeedback.sheetDismissed() }
        ) {
            AccountDeletionSheetView(
                errorMessage: $accountDeletionErrorMessage,
                hasAppleBilling: hasAppleBilling,
                onDelete: performAccountDeletion
            )
        }
        .alert(
            "Account Deleted",
            isPresented: Binding(
                get: { accountDeletionFeedback.isConfirmationPresented },
                set: { accountDeletionFeedback.setConfirmationPresented($0) }
            )
        ) {
            Button("OK") {}
        } message: {
            Text("Your Bochi account was successfully deleted.")
        }
    }

    private var gameplaySection: some View {
        Section("Gameplay") {
            NavigationLink {
                ThemeSettingsView()
            } label: {
                HStack {
                    Label("Themes", systemImage: "paintpalette")
                    Spacer()
                    if !premiumAccessStore.hasPremiumAccess(authManager: authManager) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(theme.premiumText())
                    }
                }
            }
        }
    }

    private var entityRowsSection: some View {
        Section {
            Toggle(
                "Details Row",
                isOn: Binding(
                    get: { userSettingsStore.showsEntityRowDetails },
                    set: { userSettingsStore.setShowsEntityRowDetails($0) }
                )
            )
        } header: {
            Text("Entity Views")
        } footer: {
            Text("Controls whether detail pills appear under item names in all task, recurring task, reward, earn, and search rows. This display preference stays on this device.")
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
                        .foregroundStyle(theme.secondaryText())
                }
            }

            if let lastErrorMessage = syncManager.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(theme.lowContrastText(for: .reward))
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
                Text("Sign in with Apple before sync can back up this device.")
            } else {
                Text("Changes are pushed after a short pause, remote updates are polled in the background, and a manual sync is available here.")
            }
        }
    }

    private var syncStatusColor: Color {
        switch syncManager.status {
        case .idle:
            return theme.secondaryText()
        case .syncing:
            return theme.infoText()
        case .synced:
            return theme.positiveText()
        case .error:
            return theme.destructiveText()
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        switch authManager.sessionState {
        case .signedOutFree:
            signedOutSection(
                title: "Local-Only Mode",
                systemImage: "iphone",
                detail: "Your tasks stay on this device until you sign in with Apple. Sign in to sync and back up your progress."
            )
        case .signedOutPremiumRestored:
            signedOutSection(
                title: "Premium On This Device",
                systemImage: "crown",
                detail: "An Apple purchase is active on this device. Sign in with Apple to back it up and use it across devices."
            )
        case .signedInFree:
            signedInSection(
                title: "Signed in with Apple",
                systemImage: "person.crop.circle"
            )
        case .signedInPremiumApple:
            signedInSection(
                title: "Signed in with Apple",
                systemImage: "person.crop.circle"
            )
        case .signedInPremiumWeb:
            signedInSection(
                title: "Signed in with Apple",
                systemImage: "person.crop.circle"
            )
        case .signedInLapsed:
            signedInSection(
                title: "Signed in with Apple",
                systemImage: "person.crop.circle"
            )
        }
    }

    private func signedOutSection(title: String, systemImage: String, detail: String) -> some View {
        Group {
            Section("Account") {
                Label(title, systemImage: systemImage)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText())

                AppleSignInButtonView(
                    errorMessage: $authErrorMessage,
                    isLoading: $isSigningInWithApple
                )

                if isSigningInWithApple {
                    ProgressView("Signing in...")
                }

                if let authErrorMessage {
                    Text(authErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(theme.lowContrastText(for: .reward))
                }
            }
        }
    }

    private func signedInSection(title: String, systemImage: String) -> some View {
        Group {
            Section("Account") {
                if let user = authManager.user {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText())
                        }
                    } icon: {
                        Image(systemName: systemImage)
                    }
                }

                Button("Log Out") {
                    Task { await authManager.logout() }
                }
                .foregroundStyle(theme.destructiveText())
            }

            if authManager.hasUnlinkedAppleEntitlement {
                Section("Apple Purchase") {
                    Text("This device has an Apple premium entitlement, but it is not linked to this account yet. Premium sync features stay locked until the purchase is linked.")
                        .font(.footnote)
                        .foregroundStyle(theme.secondaryText())
                }
            }
        }
    }

    private var hasAppleBilling: Bool {
        authManager.user?.subscriptionSource == .apple || authManager.localAppleEntitlement.isActive
    }

    private var premiumSection: some View {
        Section("Premium") {
            premiumStatusRow

            Text(premiumStatusDetail)
                .font(.footnote)
                .foregroundStyle(theme.secondaryText())

            restorePurchaseButton

            if let restoreMessage {
                Text(restoreMessage)
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText())
            }
        }
    }

    @ViewBuilder
    private var dangerZoneSection: some View {
        if !authManager.isLoading, authManager.user != nil {
            Section("Danger Zone") {
                Button(role: .destructive) {
                    accountDeletionErrorMessage = nil
                    isAccountDeletionSheetPresented = true
                } label: {
                    Label("Delete Account", systemImage: "trash")
                }
                .disabled(authManager.isDeletingAccount)
            }
        }
    }

    private var legalSection: some View {
        Section("Legal") {
            legalDocumentLink(
                title: "Terms of Use (EULA)",
                systemImage: "doc.text",
                destination: AppConfiguration.termsOfUseURL
            )

            legalDocumentLink(
                title: "Privacy Policy",
                systemImage: "hand.raised",
                destination: AppConfiguration.privacyPolicyURL
            )
        }
    }

    private func legalDocumentLink(title: String, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            Label(title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private var premiumStatusRow: some View {
        if premiumAccessStore.hasPremiumAccess(authManager: authManager) {
            Label(premiumStatusTitle, systemImage: premiumStatusIconName)
        } else {
            Button {
                isPremiumUpsellPresented = true
            } label: {
                Label(premiumStatusTitle, systemImage: premiumStatusIconName)
            }
        }
    }

    private var premiumStatusTitle: String {
        switch authManager.sessionState {
        case .signedOutFree, .signedInFree:
            return "Not Premium"
        case .signedOutPremiumRestored:
            return "Premium On This Device"
        case .signedInPremiumApple:
            return "Premium via Apple"
        case .signedInPremiumWeb:
            return "Premium via Account"
        case .signedInLapsed:
            return "Premium Lapsed"
        }
    }

    private var premiumStatusIconName: String {
        switch authManager.sessionState {
        case .signedOutPremiumRestored, .signedInPremiumApple:
            return "crown.fill"
        case .signedInPremiumWeb:
            return "sparkles"
        case .signedInLapsed:
            return "clock.arrow.circlepath"
        case .signedOutFree, .signedInFree:
            return "crown"
        }
    }

    private var premiumStatusDetail: String {
        switch authManager.sessionState {
        case .signedOutFree:
            return "Premium features are locked on this device. Restore an Apple purchase here if you bought one before."
        case .signedOutPremiumRestored:
            return "An Apple purchase is active on this device. Sign in with Apple to link it to an account."
        case .signedInFree:
            return "This account can sync, but premium features are locked until a purchase is linked."
        case .signedInPremiumApple:
            return premiumDetail(fallback: "Premium is active through Apple.")
        case .signedInPremiumWeb:
            return premiumDetail(fallback: "Premium is active through this account.")
        case .signedInLapsed:
            return premiumDetail(fallback: "Premium access is no longer active for this account.")
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
            let result = try await authManager.restorePurchases()
            switch result {
            case .activeOnDeviceNeedsAccount:
                restoreMessage = "Premium is now active on this device. Sign in to link it to an account later."
            case .activeForAccount:
                restoreMessage = "Premium access is active."
            case .activeOnDeviceAccountLinkFailed:
                restoreMessage = "Premium is active on this device, but could not link to this account. Check your connection and try Restore Apple Purchase again."
            case .inactive:
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

    private func performAccountDeletion() async {
        accountDeletionErrorMessage = nil

        do {
            try await authManager.deleteAccount()
            accountDeletionFeedback.deletionSucceeded()
            isAccountDeletionSheetPresented = false
        } catch {
            if let apiError = error as? ApiError {
                accountDeletionErrorMessage = apiError.userFacingMessage
            } else {
                accountDeletionErrorMessage = ApiError.networkFailure(error).userFacingMessage
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

private struct AccountDeletionSheetView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @Binding var errorMessage: String?
    let hasAppleBilling: Bool
    let onDelete: () async -> Void

    private let subscriptionURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        NavigationStack {
            List {
                if hasAppleBilling {
                    Section {
                        Link(destination: subscriptionURL) {
                            Label("Manage Apple Subscription", systemImage: "creditcard")
                        }
                    } footer: {
                        Text("Deleting your Bochi account does not cancel billing managed by Apple. Cancel your subscription separately if you do not want it to renew.")
                    }
                }

                Section {
                    Text("This cannot be undone. Your Bochi account, synced tasks, recurring tasks, rewards, timers, tags, point history, and sync data will be permanently deleted.")
                        .font(.footnote)

                    Button(role: .destructive) {
                        Task { await onDelete() }
                    } label: {
                        if authManager.isDeletingAccount {
                            Label("Deleting…", systemImage: "trash")
                        } else {
                            Label("Delete Account", systemImage: "trash")
                        }
                    }
                    .disabled(authManager.isDeletingAccount)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Delete Account")
                } footer: {
                    Text("You will be signed out on this device after deletion completes.")
                }
            }
            .navigationTitle("Delete Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(authManager.isDeletingAccount)
                }
            }
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
    let previewTimerStore = TimerStore()
    let previewTaskDependencyStore = TaskDependencyStore()
    let previewRecurringTaskStore = RecurringTaskStore()
    let previewTradeStore = TradeStore()
    let previewSettingsStore = UserSettingsStore()
    let previewBalanceStore = BalanceStore()
    let previewRewardDependencyStore = RewardDependencyStore()
    let previewReminderStore = ReminderStore()
    let previewListPreferencesStore = ListPreferencesStore()
    let previewPremiumAccessStore = PremiumAccessStore()

    SettingsView()
        .environment(previewAuthManager)
        .environment(previewSettingsStore)
        .environment(previewBalanceStore)
        .environment(previewListPreferencesStore)
        .environment(previewPremiumAccessStore)
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
                rewardStore: RewardStore(),
                tradeStore: previewTradeStore,
                tagStore: TagStore(),
                balanceStore: previewBalanceStore,
                userSettingsStore: previewSettingsStore,
                reminderStore: previewReminderStore,
                listPreferencesStore: previewListPreferencesStore
            )
        )
}
