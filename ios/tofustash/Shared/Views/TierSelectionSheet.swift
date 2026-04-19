import SwiftUI

struct TierSelectionSheet<Tier: PricingTierOption>: View {
    let title: String
    let options: [Tier]
    let currentSelection: Tier?
    let onSave: (Tier?) -> Void
    let onUnset: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var draftSelection: Tier?

    init(
        title: String,
        options: [Tier] = Array(Tier.allCases),
        currentSelection: Tier?,
        onSave: @escaping (Tier?) -> Void,
        onUnset: (() -> Void)? = nil
    ) {
        self.title = title
        self.options = options
        self.currentSelection = currentSelection
        self.onSave = onSave
        self.onUnset = onUnset
        _draftSelection = State(initialValue: currentSelection ?? options.first)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                selectedTierTitle

                tierSelector

                selectedTierDetails

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 0)
            .padding(.bottom, 20)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if let onUnset {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Unset") {
                            onUnset()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draftSelection)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.thinMaterial)
        .presentationContentInteraction(.scrolls)
    }

    private var selectedTierTitle: some View {
        Group {
            if let selected = draftSelection {
                Text(selected.displayName)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
            }
        }
    }

    private var tierSelector: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                Button {
                    draftSelection = option
                } label: {
                    Text("\(index + 1)")
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(draftSelection == option ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(draftSelection == option ? Color.orange : Color(uiColor: .systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .scaleEffect(draftSelection == option ? 1.05 : 1.0)
            }
        }
    }

    private var selectedTierDetails: some View {
        Group {
            if let selected = draftSelection {
                VStack(spacing: 12) {
                    Text(selected.shortDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Example: \(selected.example)")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
