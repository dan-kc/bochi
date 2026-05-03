import SwiftUI

enum RewardFormMode: Equatable {
    case new
    case change(Reward)

    var isNew: Bool {
        if case .new = self { return true }
        return false
    }
}

enum RewardFormFocus: Equatable {
    case maxFrequency
    case damage
    case lockout
    case tags
}

struct RewardFormSnapshot {
    let name: String
    let description: String
    let maxFrequency: Double?
    let damageTier: RewardDamageTier?
    let lockoutDurationSeconds: Int?
    let rewardId: RecordID
}

struct RewardFormView: View {
    let mode: RewardFormMode
    let initialFocus: RewardFormFocus?
    let prefill: RewardFormSnapshot?
    let onCreated: ((Reward) -> Void)?
    let onDiscard: ((RewardFormSnapshot) -> Void)?
    let onDelete: ((Reward) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(RewardStore.self) private var rewardStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(SpecialOfferStore.self) private var specialOfferStore
    @Environment(UserSettingsStore.self) private var userSettingsStore

    @State private var name = ""
    @State private var description = ""
    @State private var maxFrequency: Double? = nil
    @State private var damageTier: RewardDamageTier? = nil
    @State private var lockoutDurationSeconds: Int? = nil
    @State private var rewardId = RecordID()

    @State private var showingFrequency = false
    @State private var showingDamage = false
    @State private var showingLockout = false
    @State private var showingTags = false
    @State private var purchasingRewardRoute: RewardPurchaseRoute? = nil
    @State private var showingHistory = false
    @State private var showingDeleteConfirmation = false

    @State private var hasInitialized = false
    @State private var hasAppliedInitialLoad = false
    @State private var didPersist = false
    @FocusState private var focusedField: FieldFocus?

    enum FieldFocus: Hashable {
        case name
        case description
    }

    init(
        mode: RewardFormMode = .new,
        initialFocus: RewardFormFocus? = nil,
        prefill: RewardFormSnapshot? = nil,
        onCreated: ((Reward) -> Void)? = nil,
        onDiscard: ((RewardFormSnapshot) -> Void)? = nil,
        onDelete: ((Reward) -> Void)? = nil
    ) {
        self.mode = mode
        self.initialFocus = initialFocus
        self.prefill = prefill
        self.onCreated = onCreated
        self.onDiscard = onDiscard
        self.onDelete = onDelete
    }

    private var rewardTags: [Tag] {
        tagStore.tagsForReward(rewardId: rewardId)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var isNewMode: Bool {
        mode.isNew
    }

    private var hasContent: Bool {
        Self.hasContent(
            name: trimmedName,
            description: description,
            maxFrequency: maxFrequency,
            damageTier: damageTier,
            lockoutDurationSeconds: lockoutDurationSeconds,
            tagCount: rewardTags.count,
            isFirstReward: false
        )
    }

    private var isEditingText: Bool {
        focusedField != nil
    }

    // The price preview follows the currently visible draft so the user sees
    // how changing max frequency or damage affects the cost before leaving.
    private var draftRewardForPurchase: Reward? {
        guard case .change(let existingReward) = mode else { return nil }

        return Reward(
            id: existingReward.id,
            name: Self.nameForAutoSave(name).isEmpty ? existingReward.name : Self.nameForAutoSave(name),
            description: description,
            createdAt: existingReward.createdAt,
            updatedAt: existingReward.updatedAt,
            deletedAt: existingReward.deletedAt,
            maxFrequency: maxFrequency,
            damageTier: damageTier,
            lockoutDurationSeconds: lockoutDurationSeconds
        )
    }

    private var isLocked: Bool {
        guard let reward = draftRewardForPurchase else { return false }
        return RewardLockout.isLocked(reward: reward, tradeStore: tradeStore)
    }

    private var lockoutSummary: String? {
        guard let reward = draftRewardForPurchase else { return nil }
        guard let remainingSeconds = RewardLockout.remainingSeconds(reward: reward, tradeStore: tradeStore) else {
            return nil
        }
        return DurationFormatting.countdown(secondsRemaining: remainingSeconds)
    }

    private var currentPrice: Int {
        guard let reward = draftRewardForPurchase else { return 0 }
        let purchaseDates = tradeStore.rewardPurchaseDates(rewardId: reward.id)
        let allRewards = rewardStore.activeRewards.map { existing in
            existing.id == reward.id ? reward : existing
        }
        return RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: allRewards,
            purchaseDates: purchaseDates,
            generalDifficulty: userSettingsStore.generalDifficulty,
            specialOfferModifierPercent: specialOfferStore.activeModifierPercent(for: .reward, entityID: reward.id)
        )
    }

    private var lastPurchasedAt: Date? {
        guard let reward = draftRewardForPurchase else { return nil }
        return tradeStore.rewardPurchaseDates(rewardId: reward.id).max()
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        textFieldsSection
                            .padding(.horizontal, 16)

                        if !rewardTags.isEmpty {
                            TagPillsRow(tags: rewardTags, size: .form, leadingInset: 16)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    showingTags = true
                                }
                                .opacity(isEditingText ? 0 : 1)
                                .allowsHitTesting(!isEditingText)
                        }

                        PillRow(pills: buildPills(), leadingInset: 16, trailingInset: 16)
                            .opacity(isEditingText ? 0 : 1)
                            .allowsHitTesting(!isEditingText)

                        if let lastPurchasedAt {
                            Text(RecentActivitySummary.text(prefix: "Last purchased", date: lastPurchasedAt))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .opacity(isEditingText ? 0 : 1)
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            Color.clear.frame(height: isNewMode ? 16 : 94)
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)

                floatingControls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .opacity(isEditingText ? 0 : 1)
                    .allowsHitTesting(!isEditingText)
            }
            .navigationTitle(isNewMode ? "New Reward" : "Edit Reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isNewMode {
                        Button("Cancel") {
                            dismiss()
                        }
                    } else if case .change = mode {
                        Menu {
                            Button("History") {
                                showingHistory = true
                            }

                            Button("Delete Reward", role: .destructive) {
                                showingDeleteConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityIdentifier("reward.form.menu")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditingText ? "Done" : (isNewMode ? "Add" : "Done")) {
                        if isEditingText {
                            focusedField = nil
                            return
                        }

                        if isNewMode {
                            guard !trimmedName.isEmpty else { return }
                            guard let reward = persistReward() else { return }
                            didPersist = true
                            onCreated?(reward)
                        } else {
                            didPersist = true
                            _ = persistReward()
                        }
                        dismiss()
                    }
                    .disabled(!isEditingText && isNewMode && trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.thinMaterial)
        .presentationContentInteraction(.scrolls)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeInOut(duration: 0.18), value: isEditingText)
        .sheet(isPresented: $showingFrequency) {
            RewardFrequencyModal(maxFrequency: $maxFrequency)
        }
        .sheet(isPresented: $showingDamage) {
            TierSelectionSheet(
                title: "Set Damage",
                currentSelection: damageTier,
                onSave: { damageTier = $0 },
                onUnset: damageTier != nil ? { damageTier = nil } : nil
            )
        }
        .sheet(isPresented: $showingLockout) {
            LockoutDurationModal(durationSeconds: $lockoutDurationSeconds)
        }
        .sheet(isPresented: $showingTags) {
            TagsView(selectionMode: .assignment(.reward(rewardId)))
        }
        .sheet(item: $purchasingRewardRoute) { route in
            RewardPurchaseModalView(
                reward: route.reward,
                resolvedSpecialOffer: route.resolvedSpecialOffer
            ) {
                dismiss()
            }
        }
        .sheet(isPresented: $showingHistory) {
            TradeHistorySheetView(
                filter: .reward(rewardId),
                detents: [.large]
            )
        }
        .alert("Delete Reward?", isPresented: $showingDeleteConfirmation) {
            if case .change(let reward) = mode {
                Button("Delete", role: .destructive) {
                    dismiss()
                    onDelete?(reward)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .task {
            initializeIfNeeded()
        }
        .onChange(of: name) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: description) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: maxFrequency) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: damageTier) { _, _ in
            autoSaveIfNeeded()
        }
        .onChange(of: lockoutDurationSeconds) { _, _ in
            autoSaveIfNeeded()
        }
        .onDisappear {
            if isNewMode && !didPersist && hasContent {
                onDiscard?(RewardFormSnapshot(
                    name: name,
                    description: description,
                    maxFrequency: maxFrequency,
                    damageTier: damageTier,
                    lockoutDurationSeconds: lockoutDurationSeconds,
                    rewardId: rewardId
                ))
            }
        }
    }

    private var textFieldsSection: some View {
        EntityFormTextFieldsSection(
            name: $name,
            description: $description,
            focusedField: $focusedField,
            nameFocus: .name,
            descriptionFocus: .description
        )
    }

    private var floatingControls: some View {
        VStack(spacing: 10) {
            if !isNewMode {
                if isLocked {
                    lockedPurchaseSummary
                } else {
                    purchaseButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lockedPurchaseSummary: some View {
        HStack {
            Label("Locked", systemImage: "lock.fill")
            Spacer()
            if let lockoutSummary {
                Text(lockoutSummary)
                    .fontWeight(.semibold)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.thinMaterial, in: Capsule())
    }

    private var purchaseButton: some View {
        TofuActionButton(amount: currentPrice, polarity: .spending, layout: .expanded(title: "Buy Reward")) {
            guard let persistedReward = persistReward() else { return }
            didPersist = true
            purchasingRewardRoute = RewardPurchaseRoute(
                reward: persistedReward,
                resolvedSpecialOffer: specialOfferStore.activeOffer(for: .reward, entityID: persistedReward.id)
            )
        }
    }

    static func hasContent(
        name: String,
        description: String,
        maxFrequency: Double?,
        damageTier: RewardDamageTier?,
        lockoutDurationSeconds: Int?,
        tagCount: Int,
        isFirstReward: Bool = false
    ) -> Bool {
        EntityFormSupport.hasRecoverableContent(
            name: name,
            description: description,
            primaryValueIsSet: maxFrequency != nil,
            secondaryValueIsSet: damageTier != nil || lockoutDurationSeconds != nil,
            tagCount: tagCount,
            ignoreSecondaryValue: isFirstReward
        )
    }

    static func nameForAutoSave(_ name: String) -> String {
        EntityFormSupport.trimmedName(name)
    }

    static func buildPillData(
        hasTagsApplied: Bool,
        damageTier: RewardDamageTier?,
        maxFrequency: Double?,
        lockoutDurationSeconds: Int?
    ) -> [EntityFormPillConfig] {
        let frequencyLabel = FrequencyConversion.formatSummary(maxFrequency).map { "Max \($0)" } ?? "Max Frequency"
        let lockoutLabel = DurationFormatting.summary(seconds: lockoutDurationSeconds) ?? "Lockout"
        return [
            EntityFormPillConfig(id: "tags", label: "Tags", icon: "tag", isSet: hasTagsApplied),
            EntityFormPillConfig(id: "damage", label: damageTier?.displayName ?? "Damage", icon: "flame", isSet: damageTier != nil),
            EntityFormPillConfig(id: "frequency", label: frequencyLabel, icon: "clock", isSet: maxFrequency != nil),
            EntityFormPillConfig(id: "lockout", label: lockoutLabel, icon: "lock", isSet: lockoutDurationSeconds != nil)
        ]
    }

    private func buildPills() -> [PillItem] {
        let configs = Self.buildPillData(
            hasTagsApplied: !rewardTags.isEmpty,
            damageTier: damageTier,
            maxFrequency: maxFrequency,
            lockoutDurationSeconds: lockoutDurationSeconds
        )
        let actions: [String: () -> Void] = [
            "tags": { showingTags = true },
            "damage": { showingDamage = true },
            "frequency": { showingFrequency = true },
            "lockout": { showingLockout = true },
        ]

        return EntityFormSupport.buildPills(
            configs: configs,
            actions: actions
        )
    }

    private func initializeIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        if let prefill, mode.isNew {
            name = prefill.name
            description = prefill.description
            maxFrequency = prefill.maxFrequency
            damageTier = prefill.damageTier
            lockoutDurationSeconds = prefill.lockoutDurationSeconds
            rewardId = prefill.rewardId
        } else if case .change(let reward) = mode {
            name = reward.name
            description = reward.description
            maxFrequency = reward.maxFrequency
            damageTier = reward.damageTier
            lockoutDurationSeconds = reward.lockoutDurationSeconds
            rewardId = reward.id
        }

        hasAppliedInitialLoad = true

        guard let initialFocus else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch initialFocus {
            case .maxFrequency:
                showingFrequency = true
            case .damage:
                showingDamage = true
            case .lockout:
                showingLockout = true
            case .tags:
                showingTags = true
            }
        }
    }

    private func autoSaveIfNeeded() {
        guard !isNewMode, hasAppliedInitialLoad else { return }
        _ = persistReward()
    }

    @discardableResult
    private func persistReward() -> Reward? {
        if case .new = mode {
            return rewardStore.addReward(
                id: rewardId,
                name: name,
                description: description,
                maxFrequency: maxFrequency,
                damageTier: damageTier,
                lockoutDurationSeconds: lockoutDurationSeconds
            )
        }

        rewardStore.updateReward(
            id: rewardId,
            name: Self.nameForAutoSave(name),
            description: description,
            maxFrequency: .some(maxFrequency),
            damageTier: .some(damageTier),
            lockoutDurationSeconds: .some(lockoutDurationSeconds)
        )

        return draftRewardForPurchase
    }
}
