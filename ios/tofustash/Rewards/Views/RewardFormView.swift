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
    let damageRank: String?
    let rewardId: String
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
    @State private var damageRank: String? = nil
    @State private var rewardId: String = UUID().uuidString

    @State private var showingFrequency = false
    @State private var showingDamage = false
    @State private var showingTags = false
    @State private var purchasingReward: Reward? = nil
    @State private var showingFirstRewardAlert = false
    @State private var showingDeleteConfirmation = false

    @State private var hasInitialized = false
    @State private var hasAppliedInitialLoad = false
    @State private var didPersist = false
    @State private var timeBucket = RewardPriceCalculation.getCurrentTimeBucket()
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

    private var isFirstReward: Bool {
        Self.isFirstReward(mode: mode, activeRewardsCount: rewardStore.activeRewards.count)
    }

    private var hasComparableRewards: Bool {
        let rankedCount = rewardStore.activeRewards
            .filter { $0.damageRank != nil && $0.id != rewardId }
            .count
        return rankedCount > 0
    }

    private var canPurchase: Bool {
        maxFrequency != nil && damageRank != nil
    }

    private var hasContent: Bool {
        Self.hasContent(
            name: trimmedName,
            description: description,
            maxFrequency: maxFrequency,
            damageRank: damageRank,
            tagCount: rewardTags.count,
            isFirstReward: isFirstReward
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
            damageRank: damageRank
        )
    }

    private var currentPrice: Int {
        guard let reward = draftRewardForPurchase else { return 0 }
        guard reward.canPurchase else { return 0 }
        let purchases = tradeStore.rewardPurchasesInPeriod(rewardId: reward.id, days: 60)
        let allRewards = rewardStore.activeRewards.map { existing in
            existing.id == reward.id ? reward : existing
        }
        return RewardPriceCalculation.calculatePrice(
            reward: reward,
            allRewards: allRewards,
            purchasesInPeriod: purchases,
            timeBucket: timeBucket,
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
                            TagPillsRow(tags: rewardTags, leadingInset: 16)
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
            DamageRankerView(
                rewardName: trimmedName.isEmpty ? "New Reward" : trimmedName,
                damageRank: $damageRank,
                currentDamageRank: damageRank,
                excludeRewardId: mode.isNew ? nil : rewardId
            )
        }
        .sheet(isPresented: $showingTags) {
            TagsView(target: .reward(rewardId))
        }
        .sheet(item: $purchasingReward) { reward in
            RewardPurchaseModalView(reward: reward) {
                dismiss()
            }
        }
        .alert("Damage Set", isPresented: $showingFirstRewardAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("There are no other rewards to compare against. Add more rewards to adjust damage ranking.")
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
        .task {
            while !Task.isCancelled {
                let nanos = RewardPriceCalculation.nanosUntilNextBucket()
                try? await Task.sleep(nanoseconds: nanos)
                timeBucket = RewardPriceCalculation.getCurrentTimeBucket()
            }
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
        .onChange(of: damageRank) { _, _ in
            autoSaveIfNeeded()
        }
        .onDisappear {
            if isNewMode && !didPersist && hasContent {
                onDiscard?(RewardFormSnapshot(
                    name: name,
                    description: description,
                    maxFrequency: maxFrequency,
                    damageRank: damageRank,
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
            if !isNewMode && canPurchase {
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
        damageRank: String?,
        tagCount: Int,
        isFirstReward: Bool = false
    ) -> Bool {
        let hasDamage = isFirstReward ? false : damageRank != nil

        return !name.isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || maxFrequency != nil
            || hasDamage
            || tagCount > 0
    }

    static func nameForAutoSave(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
    }

    static func isFirstReward(mode: RewardFormMode, activeRewardsCount: Int) -> Bool {
        mode.isNew && activeRewardsCount == 0
    }

    static func defaultDamageRankForFirstReward() -> String {
        DamageRanker.makeSession(rewardName: "", rankedRewards: []).generateRank()
    }

    static func buildPillData(
        hasTagsApplied: Bool,
        damageRank: String?,
        maxFrequency: Double?
    ) -> [PillItem] {
        let frequencyLabel = FrequencyConversion.formatSummary(maxFrequency).map { "Max \($0)" } ?? "Max Frequency"
        return [
            PillItem(id: "tags", label: "Tags", icon: "tag", isSet: hasTagsApplied),
            PillItem(id: "damage", label: "Damage", icon: "flame", isSet: damageRank != nil),
            PillItem(id: "frequency", label: frequencyLabel, icon: "clock", isSet: maxFrequency != nil),
        ]
    }

    private func buildPills() -> [PillItem] {
        var pills = Self.buildPillData(
            hasTagsApplied: !rewardTags.isEmpty,
            damageRank: damageRank,
            maxFrequency: maxFrequency
        )

        let actions: [String: () -> Void] = [
            "tags": { showingTags = true },
            "damage": {
                if hasComparableRewards {
                    showingDamage = true
                } else {
                    showingFirstRewardAlert = true
                }
            },
            "frequency": { showingFrequency = true },
        ]

        for index in pills.indices {
            pills[index].action = actions[pills[index].id]
            let shouldPulse =
                (pills[index].id == "frequency" && maxFrequency == nil) ||
                (pills[index].id == "damage" && damageRank == nil)
            pills[index].animating = shouldPulse
        }

        return pills
    }

    private func initializeIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        if let prefill, mode.isNew {
            name = prefill.name
            description = prefill.description
            maxFrequency = prefill.maxFrequency
            damageRank = prefill.damageRank
            rewardId = prefill.rewardId
        } else if case .change(let reward) = mode {
            name = reward.name
            description = reward.description
            maxFrequency = reward.maxFrequency
            damageRank = reward.damageRank
            rewardId = reward.id
        }

        // Behaviour: the very first reward gets the midpoint damage rank because
        // there is nothing else to compare it against yet.
        if isFirstReward && damageRank == nil {
            damageRank = Self.defaultDamageRankForFirstReward()
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
                damageRank: damageRank
            )
        }

        rewardStore.updateReward(
            id: rewardId,
            name: Self.nameForAutoSave(name),
            description: description,
            maxFrequency: .some(maxFrequency),
            damageRank: .some(damageRank)
        )

        return draftRewardForPurchase
    }
}
