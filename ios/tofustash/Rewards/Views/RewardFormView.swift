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
    case tags
}

struct RewardFormSnapshot {
    let name: String
    let description: String
    let maxFrequency: Double?
    let damageTier: RewardDamageTier?
    let rewardId: RecordID
}

struct RewardFormView: View {
    let mode: RewardFormMode
    let initialFocus: RewardFormFocus?
    let prefill: RewardFormSnapshot?
    let onDiscard: ((RewardFormSnapshot) -> Void)?
    let onDelete: ((Reward) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(RewardStore.self) private var rewardStore
    @Environment(TagStore.self) private var tagStore
    @Environment(TradeStore.self) private var tradeStore
    @Environment(UserSettingsStore.self) private var userSettingsStore

    @State private var name = ""
    @State private var description = ""
    @State private var maxFrequency: Double? = nil
    @State private var damageTier: RewardDamageTier? = nil
    @State private var rewardId = RecordID()

    @State private var showingFrequency = false
    @State private var showingDamage = false
    @State private var showingTags = false
    @State private var purchasingReward: Reward? = nil
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
        onDiscard: ((RewardFormSnapshot) -> Void)? = nil,
        onDelete: ((Reward) -> Void)? = nil
    ) {
        self.mode = mode
        self.initialFocus = initialFocus
        self.prefill = prefill
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
            damageTier: damageTier
        )
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
            generalDifficulty: userSettingsStore.generalDifficulty
        )
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

                        PillRow(pills: buildPills(), leadingInset: 16)
                            .opacity(isEditingText ? 0 : 1)
                            .allowsHitTesting(!isEditingText)

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
                            Button("Delete Reward", role: .destructive) {
                                showingDeleteConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditingText ? "Done" : (isNewMode ? "Add" : "Done")) {
                        if isEditingText {
                            focusedField = nil
                            return
                        }

                        guard isNewMode ? !trimmedName.isEmpty : true else { return }
                        didPersist = true
                        _ = persistReward()
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
        .sheet(isPresented: $showingTags) {
            TagsView(selectionMode: .assignment(.reward(rewardId)))
        }
        .sheet(item: $purchasingReward) { reward in
            RewardPurchaseModalView(reward: reward) {
                dismiss()
            }
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
        .onDisappear {
            if isNewMode && !didPersist && hasContent {
                onDiscard?(RewardFormSnapshot(
                    name: name,
                    description: description,
                    maxFrequency: maxFrequency,
                    damageTier: damageTier,
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
                TofuActionButton(amount: currentPrice, polarity: .spending, layout: .expanded(title: "Buy Reward")) {
                    guard let persistedReward = persistReward() else { return }
                    didPersist = true
                    purchasingReward = persistedReward
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func hasContent(
        name: String,
        description: String,
        maxFrequency: Double?,
        damageTier: RewardDamageTier?,
        tagCount: Int,
        isFirstReward: Bool = false
    ) -> Bool {
        EntityFormSupport.hasRecoverableContent(
            name: name,
            description: description,
            primaryValueIsSet: maxFrequency != nil,
            secondaryValueIsSet: damageTier != nil,
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
        maxFrequency: Double?
    ) -> [EntityFormPillConfig] {
        let frequencyLabel = FrequencyConversion.formatSummary(maxFrequency).map { "Max \($0)" } ?? "Max Frequency"
        return [
            EntityFormPillConfig(id: "tags", label: "Tags", icon: "tag", isSet: hasTagsApplied),
            EntityFormPillConfig(id: "damage", label: damageTier?.displayName ?? "Damage", icon: "flame", isSet: damageTier != nil),
            EntityFormPillConfig(id: "frequency", label: frequencyLabel, icon: "clock", isSet: maxFrequency != nil),
        ]
    }

    private func buildPills() -> [PillItem] {
        let configs = Self.buildPillData(
            hasTagsApplied: !rewardTags.isEmpty,
            damageTier: damageTier,
            maxFrequency: maxFrequency
        )
        let actions: [String: () -> Void] = [
            "tags": { showingTags = true },
            "damage": { showingDamage = true },
            "frequency": { showingFrequency = true },
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
            rewardId = prefill.rewardId
        } else if case .change(let reward) = mode {
            name = reward.name
            description = reward.description
            maxFrequency = reward.maxFrequency
            damageTier = reward.damageTier
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
                damageTier: damageTier
            )
        }

        rewardStore.updateReward(
            id: rewardId,
            name: Self.nameForAutoSave(name),
            description: description,
            maxFrequency: .some(maxFrequency),
            damageTier: .some(damageTier)
        )

        return draftRewardForPurchase
    }
}
