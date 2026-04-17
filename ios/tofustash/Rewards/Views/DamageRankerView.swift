import SwiftUI

// SwiftUI wrapper around the pure DamageRanker session logic. This mirrors the
// difficulty ranker flow, but the comparison question is framed around how much
// damage the reward does to the user's goals.
struct DamageRankerView: View {
    @Binding var damageRank: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(RewardStore.self) private var rewardStore

    @State private var session: DamageRanker.Session
    @State private var isInitialized = false
    @State private var showCheckmark = false

    let excludeRewardId: String?
    let currentDamageRank: String?

    init(
        rewardName: String,
        damageRank: Binding<String?>,
        currentDamageRank: String? = nil,
        excludeRewardId: String? = nil
    ) {
        self._damageRank = damageRank
        self.currentDamageRank = currentDamageRank
        self.excludeRewardId = excludeRewardId
        self._session = State(initialValue: DamageRanker.makeSession(
            rewardName: rewardName,
            rankedRewards: []
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isInitialized {
                    Color.clear
                } else if session.isComplete {
                    completionView
                } else if let comparison = session.currentComparison {
                    comparisonView(comparison)
                }
            }
            .navigationTitle(session.isComplete ? "" : "Set Damage")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.large])
            .presentationBackground(.thinMaterial)
            .presentationContentInteraction(.scrolls)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .toolbar(session.isComplete ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if Self.shouldShowUnsetButton(currentDamageRank: currentDamageRank) {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Unset") {
                            damageRank = nil
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                initializeSession()
            }
        }
    }

    private var completionView: some View {
        VStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .scaleEffect(showCheckmark ? 1.0 : 0.0)
                .animation(.spring(duration: 0.4, bounce: 0.5), value: showCheckmark)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                showCheckmark = true
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        }
    }

    private func comparisonView(_ comparison: Reward) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("~\(max(1, session.estimatedComparisons - session.comparisonCount)) comparison\(session.estimatedComparisons - session.comparisonCount != 1 ? "s" : "") remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("New Reward")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(session.rewardName)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.fill.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("Is this reward more or less damaging than:")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Compare with")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(comparison.name)
                        .font(.headline)
                    if !comparison.description.isEmpty {
                        Text(comparison.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.fill.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 12) {
                    Button {
                        session.chooseMoreDamaging()
                        checkCompletion()
                    } label: {
                        Text("More Damaging")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        session.chooseLessDamaging()
                        checkCompletion()
                    } label: {
                        Text("Less Damaging")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding()
        }
    }

    static func shouldShowUnsetButton(currentDamageRank: String?) -> Bool {
        currentDamageRank != nil
    }

    private func initializeSession() {
        let ranked = rewardStore.activeRewards
            .filter { $0.damageRank != nil && $0.id != excludeRewardId }
            .sorted { ($0.damageRank ?? "") > ($1.damageRank ?? "") }

        session = DamageRanker.makeSession(
            rewardName: session.rewardName,
            rankedRewards: ranked
        )

        isInitialized = true

        if session.isComplete {
            damageRank = session.generateRank()
        }
    }

    private func checkCompletion() {
        if session.isComplete {
            damageRank = session.generateRank()
        }
    }
}
