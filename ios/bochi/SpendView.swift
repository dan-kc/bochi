import SwiftUI

private struct RewardFormRoute: Identifiable {
    let id = UUID()
    let mode: RewardFormMode
    let initialFocus: RewardFormFocus?
    let prefill: RewardFormSnapshot?
}

private struct RewardListProjectionToken: Equatable {
    let rewards: [Reward]
    let rewardTaskDependencies: [RewardTaskDependency]
    let rewardRecurringTaskDependencies: [RewardRecurringTaskDependency]
    let tasks: [TaskItem]
    let tags: [Tag]
    let rewardTags: [RewardTag]
    let trades: [Trade]
    let balance: Int
    let preferences: EntityListPreferences
    let hasPremiumAccess: Bool
}

private struct PendingRewardActionWarning: Identifiable {
    let id = UUID()
    let reason: EntityActionGateReason
    let entityName: String
    let actionTitle: String
    let continueAction: () -> Void
}

struct SpendView: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(RewardStore.self) private var rewardStore
    @Environment(RewardDependencyStore.self) private var rewardDependencyStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(BalanceStore.self) private var balanceStore
    @Environment(UserSettingsStore.self) private var userSettingsStore
    @Environment(AppNavigationStore.self) private var appNavigationStore
    @Environment(ListPreferencesStore.self) private var listPreferencesStore
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumAccessStore.self) private var premiumAccessStore

    @State private var formRoute: RewardFormRoute? = nil
    @State private var purchasingRewardRoute: RewardPurchaseRoute? = nil
    @State private var historyReward: Reward? = nil
    @State private var rewardToDelete: Reward? = nil
    @State private var premiumUpsellFeature: PremiumUpsellFeature? = nil
    @State private var showingRefundFeedback = false
    @State private var pendingActionWarning: PendingRewardActionWarning? = nil
    @State private var pendingScrollTargetID: RecordID? = nil
    @State private var highlightedRewardID: RecordID? = nil
    @State private var listProjection: RewardListProjection?

    private var projectionToken: RewardListProjectionToken {
        RewardListProjectionToken(
            rewards: rewardStore.rewards,
            rewardTaskDependencies: rewardDependencyStore.rewardTaskDependencies,
            rewardRecurringTaskDependencies: rewardDependencyStore.rewardRecurringTaskDependencies,
            tasks: taskStore.tasks,
            tags: tagStore.tags,
            rewardTags: tagStore.rewardTags,
            trades: tradeStore.trades,
            balance: balanceStore.balance,
            preferences: listPreferencesStore.rewardPreferences,
            hasPremiumAccess: hasPremiumAccess
        )
    }

    private func rewardIsLocked(_ row: RewardListRowModel) -> Bool {
        row.isUnavailable
    }

    var body: some View {
        // User behaviour: balance animations and modal state should not cause a
        // large reward list to recompute unless data that affects rows changed.
        let projection = listProjection ?? makeListProjection()

        NavigationStack {
            EntityListScreen(
                hasAnyItems: !projection.activeRewards.isEmpty,
                visibleItemCount: projection.visibleRewardRows.count,
                emptyTitle: "Nothing to Spend On Yet",
                emptySystemImage: "gift",
                emptyDescription: "Tap + to create your first reward.",
                filteredEmptyTitle: "No Matching Spend Items",
                filteredEmptyDescription: "Try turning filters back on to see more spending options.",
                preferences: listPreferencesStore.rewardPreferences,
                tagScope: .rewards,
                availableTags: tagStore.activeTags,
                statusFilters: [.recurringTask, .hidden, .locked],
                rowIDs: projection.rowIDs,
                pendingScrollTargetID: $pendingScrollTargetID,
                onSelectSort: { option in
                    withAnimation(.default) {
                        listPreferencesStore.setRewardSort(option)
                    }
                },
                onClearFilters: listPreferencesStore.clearRewardFilters,
                onToggleStatus: { status in
                    listPreferencesStore.toggleRewardStatus(status)
                },
                onToggleTag: { tagID in
                    listPreferencesStore.toggleRewardTag(tagID)
                },
                onControlsVisibilityChange: { isVisible in
                    appNavigationStore.setRootEntityListControlsVisibility(isVisible, for: .spend)
                },
                onPendingScrollCompleted: { rewardID in
                    scheduleNewRewardHighlightFade(for: rewardID)
                }
            ) {
                ForEach(Array(projection.visibleRewardRows.enumerated()), id: \.element.id) { index, row in
                    EntityListRowSurface(
                        showsDivider: index < projection.visibleRewardRows.count - 1,
                        role: .reward,
                        isHighlighted: highlightedRewardID == row.id
                    ) {
                        rewardRow(row, isDimmed: rewardIsDimmed(row))
                    }
                    .id(row.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            // Behaviour: both swipe depths should open the same
                            // confirmation alert before the reward is removed.
                            confirmDelete(row.reward)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(theme.destructiveText())
                    }
                    .contextMenu {
                        rewardRowMenu(row)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Spend")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottomTrailing) {
                EntityListFloatingActionOverlay(
                    showsSearchButton: !projection.activeRewards.isEmpty,
                    onAdd: openNewRewardForm
                )
            }
            .sheet(item: $formRoute) { route in
                RewardFormView(
                    mode: route.mode,
                    initialFocus: route.initialFocus,
                    prefill: route.prefill,
                    onCreated: { reward in
                        queueScrollToRewardIfVisible(reward.id)
                    },
                    onDiscard: nil,
                    onDelete: { reward in
                        deleteReward(reward)
                    },
                    onDuplicate: { reward in
                        duplicateReward(reward)
                    }
                )
            }
            .sheet(item: $purchasingRewardRoute) { route in
                RewardPurchaseModalView(
                    reward: route.reward,
                    quote: route.quote,
                    allowsRestrictedPurchase: route.allowsRestrictedPurchase
                )
            }
            .sheet(item: $historyReward) { reward in
                TradeHistorySheetView(
                    filter: .reward(reward.id),
                    detents: [.large]
                )
            }
            .sheet(isPresented: $showingRefundFeedback) {
                TaskRefundFeedbackSheet {
                    showingRefundFeedback = false
                }
            }
            .sheet(item: $pendingActionWarning) { warning in
                EntityActionWarningModalView(
                    entityName: warning.entityName,
                    actionTitle: warning.actionTitle,
                    reason: warning.reason,
                    onCancel: { pendingActionWarning = nil },
                    onConfirm: {
                        let continueAction = warning.continueAction
                        pendingActionWarning = nil
                        continueAction()
                    }
                )
            }
            .fullScreenCover(item: $premiumUpsellFeature) { feature in
                PremiumUpsellView(feature: feature)
            }
            .alert(
                "Delete Reward?",
                isPresented: rewardDeleteConfirmationBinding
            ) {
                Button("Delete") {
                    if let reward = rewardToDelete {
                        deleteReward(reward)
                    }
                }
                Button("Cancel", role: .cancel) {
                    rewardToDelete = nil
                }
            } message: {
                Text("Your balance will not be affected.")
            }
            .entityListProjectionLifecycle(
                projectionToken: projectionToken,
                pendingFormToken: appNavigationStore.pendingEntityFormRequest,
                pendingRevealToken: appNavigationStore.pendingEntityRevealRequest,
                selectedTab: appNavigationStore.selectedTab,
                expectedTab: .spend,
                refreshProjection: updateListProjection,
                openPendingForm: openPendingRewardFormIfNeeded,
                revealPendingEntity: revealPendingRewardIfNeeded
            )
        }
    }

    private func updateListProjection() {
        listProjection = makeListProjection()
    }

    private func makeListProjection() -> RewardListProjection {
        SpendListProjectionBuilder.makeProjection(
            inputs: RewardListProjectionInputs(
                rewards: rewardStore.rewards,
                tasks: taskStore.tasks,
                rewardTagsByID: tagStore.tagsByRewardID(),
                activeTagIDs: tagStore.activeTagIDs,
                rewardTaskDependencies: rewardDependencyStore.rewardTaskDependencies,
                rewardRecurringTaskDependencies: rewardDependencyStore.rewardRecurringTaskDependencies,
                latestTaskTradesByTaskID: tradeStore.latestUnrefundedTaskTradesByTaskID(),
                recurringTaskCompletionCountsByRecurringTaskID: tradeStore.recurringTaskCompletionCountsByRecurringTaskID(),
                rewardPurchaseDatesByRewardID: tradeStore.rewardPurchaseDatesByRewardID(),
                latestRewardPurchasesByRewardID: tradeStore.latestUnrefundedRewardPurchasesByRewardID(),
                balance: balanceStore.balance,
                preferences: listPreferencesStore.rewardPreferences,
                hasPremiumAccess: hasPremiumAccess,
                now: Date()
            )
        )
    }

    private func rewardIsDimmed(_ row: RewardListRowModel) -> Bool {
        rewardIsLocked(row) || row.reward.hidden
    }

    private func openNewRewardForm() {
        appNavigationStore.openNewEntityForm(selectedEntity: .reward, originTab: .spend)
    }

    private func confirmDelete(_ reward: Reward) {
        rewardToDelete = reward
    }

    private var rewardDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { rewardToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    rewardToDelete = nil
                }
            }
        )
    }

    private func deleteReward(_ reward: Reward) {
        let deletedAt = Date()
        withAnimation(.default) {
            EntityDeletionService.deleteReward(
                reward,
                rewardDependencyStore: rewardDependencyStore,
                rewardStore: rewardStore,
                deletedAt: deletedAt
            )
            rewardToDelete = nil
        }
    }

    private func rewardRow(
        _ row: RewardListRowModel,
        isDimmed: Bool
    ) -> some View {
        let reward = row.reward
        let metadataItems = EntityListRowPillSupport.rewardMetadata(reward: reward)
        let pills = EntityListRowPillSupport.rewardPills(reward: reward, tags: row.tags)
        let rowStatus = row.listStatus
        let gateReason = EntityActionGateSupport.reason(
            isLocked: row.isLocked || row.isBlocked,
            lockoutSummary: lockoutSummary(for: reward),
            isHidden: reward.hidden
        )

        return HStack(alignment: rowStatus == nil ? .bottom : .center) {
            EntityListRowText(
                name: reward.name,
                description: reward.description,
                metadataItems: metadataItems,
                pills: pills,
                role: .reward,
                showsDetails: userSettingsStore.showsEntityRowDetails
            )

            EntityListRowActionColumn {
                if let rowStatus {
                    EntityListRowStatusLabel(status: rowStatus, role: .reward)
                } else if reward.canPurchase {
                    VStack(alignment: .trailing, spacing: 4) {
                        EntityListRowPriceDeltaLabel(
                            percent: PriceDeltaSupport.percent(currentPrice: row.price, basePrice: reward.basePrice),
                            role: .reward
                        )
                        BochiActionButton(
                            amount: row.price,
                            polarity: .spending,
                            layout: .compact,
                            usesMainThemeStyle: gateReason != nil,
                            themeRoleOverride: .reward
                        ) {
                            openPurchaseModal(
                                for: reward,
                                quote: row.quote,
                                warningReason: gateReason
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isDimmed ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            openChangeForm(reward, focus: nil)
        }
    }

    @ViewBuilder
    private func rewardRowMenu(_ row: RewardListRowModel) -> some View {
        let reward = row.reward

        if reward.canPurchase && !row.isSpent {
            Button {
                openPurchaseModal(
                    for: reward,
                    quote: row.quote,
                    warningReason: EntityActionGateSupport.reason(
                        isLocked: row.isLocked || row.isBlocked,
                        lockoutSummary: lockoutSummary(for: reward),
                        isHidden: reward.hidden
                    )
                )
            } label: {
                Label("Claim Reward", systemImage: "gift")
            }
        }

        if row.isSpent, row.canRefund {
            Button {
                requestRewardRefund(reward)
            } label: {
                Label(
                    hasPremiumAccess ? "Refund" : "Refund (Premium)",
                    systemImage: hasPremiumAccess ? "arrow.uturn.backward" : "crown"
                )
            }
        }

        EntityRowContextMenuActions.editHistoryDelete(
            theme: theme,
            onEdit: {
                openChangeForm(reward, focus: nil)
            },
            onDuplicate: {
                duplicateReward(reward)
            },
            onTogglePin: {
                rewardStore.setPinned(id: reward.id, pinned: !reward.pinned)
            },
            isPinned: reward.pinned,
            onToggleHidden: {
                rewardStore.setHidden(id: reward.id, hidden: !reward.hidden)
            },
            isHidden: reward.hidden,
            onViewHistory: {
                historyReward = reward
            },
            onDelete: {
                confirmDelete(reward)
            }
        )
    }

    private func requestRewardRefund(_ reward: Reward) {
        guard hasPremiumAccess else {
            premiumUpsellFeature = .refunds
            return
        }

        guard let trade = tradeStore.latestRewardPurchase(rewardId: reward.id, includeRefunded: false) else { return }

        withAnimation(.default) {
            let refundTrade = TradeRefundService.refund(
                for: trade,
                tradeStore: tradeStore,
                balanceStore: balanceStore
            )
            guard refundTrade != nil else { return }
            showingRefundFeedback = true
        }
    }

    private func openChangeForm(_ reward: Reward, focus: RewardFormFocus?) {
        formRoute = RewardFormRoute(
            mode: .change(reward),
            initialFocus: focus,
            prefill: nil
        )
    }

    private func openPurchaseModal(
        for reward: Reward,
        quote: RewardPurchaseQuote,
        warningReason: EntityActionGateReason? = nil
    ) {
        if let warningReason {
            pendingActionWarning = PendingRewardActionWarning(
                reason: warningReason,
                entityName: reward.name,
                actionTitle: "Buy Reward",
                continueAction: {
                    openPurchaseModal(
                        for: reward,
                        quote: quote,
                        allowsRestrictedPurchase: true
                    )
                }
            )
            return
        }

        openPurchaseModal(for: reward, quote: quote, allowsRestrictedPurchase: false)
    }

    private func openPurchaseModal(
        for reward: Reward,
        quote: RewardPurchaseQuote,
        allowsRestrictedPurchase: Bool
    ) {
        purchasingRewardRoute = RewardPurchaseRoute(
            reward: reward,
            quote: quote,
            allowsRestrictedPurchase: allowsRestrictedPurchase
        )
    }

    private func lockoutSummary(for reward: Reward) -> String? {
        guard let remainingSeconds = RewardLockout.remainingSeconds(
            reward: reward,
            tradeStore: tradeStore,
            hasPremiumAccess: hasPremiumAccess
        ) else {
            return nil
        }

        return DurationFormatting.countdown(secondsRemaining: remainingSeconds)
    }

    private func duplicateReward(_ reward: Reward) {
        let snapshot = EntityDuplicateSupport.snapshot(
            duplicating: reward,
            tagIDs: tagStore.tagsForReward(rewardId: reward.id).map(\.id)
        )
        EntityListViewCoordinator.scheduleDeferredAction {
            appNavigationStore.openNewEntityForm(snapshot: snapshot, originTab: .spend)
        }
    }

    private func queueScrollToRewardIfVisible(_ rewardID: RecordID) {
        EntityListViewCoordinator.queueScrollToVisibleItem(
            rewardID,
            visibleIDs: makeListProjection().rowIDs,
            highlightedID: &highlightedRewardID,
            pendingScrollTargetID: &pendingScrollTargetID
        )
    }

    private func scheduleNewRewardHighlightFade(for rewardID: RecordID) {
        EntityListViewCoordinator.scheduleHighlightFade(
            for: rewardID,
            highlightedID: { highlightedRewardID },
            setHighlightedID: { highlightedRewardID = $0 }
        )
    }

    @MainActor
    private func openPendingRewardFormIfNeeded() {
        EntityListViewCoordinator.openPendingFormIfNeeded(
            expectedTab: .spend,
            selectedTab: appNavigationStore.selectedTab,
            request: appNavigationStore.pendingEntityFormRequest,
            extractID: { route in
                guard case .reward(let rewardID) = route else { return nil }
                return rewardID
            },
            resolveEntity: { rewardID in
                rewardStore.rewards.first(where: { $0.id == rewardID && $0.deletedAt == nil })
            },
            isPresentingForm: formRoute != nil || appNavigationStore.isPresentingNewEntityForm,
            open: { reward in
                openChangeForm(reward, focus: nil)
            },
            clearRequest: { requestID in
                appNavigationStore.clearPendingEntityFormRequest(id: requestID)
            }
        )
    }

    @MainActor
    private func revealPendingRewardIfNeeded() {
        guard appNavigationStore.selectedTab == .spend else { return }
        guard let request = appNavigationStore.pendingEntityRevealRequest else { return }
        guard case .reward(let rewardID) = request.route else { return }

        queueScrollToRewardIfVisible(rewardID)
        appNavigationStore.clearPendingEntityRevealRequest(id: request.id)
    }

    private var hasPremiumAccess: Bool {
        premiumAccessStore.hasPremiumAccess(authManager: authManager)
    }
}

#Preview {
    let authManager = AuthManager(
        apiClient: AppConfiguration.makeAuthAPIClient(),
        tokenStorage: KeychainTokenStorage(),
        appleEntitlementClient: StoreKitAppleEntitlementClient()
    )

    SpendView()
        .environment(authManager)
        .environment(BalanceStore())
        .environment(TaskStore())
        .environment(RewardStore())
        .environment(RewardDependencyStore())
        .environment(TagStore())
        .environment(TradeStore())
        .environment(UserSettingsStore())
        .environment(AppNavigationStore())
        .environment(OmniSearchStore())
        .environment(ListPreferencesStore())
        .environment(PremiumAccessStore())
}
