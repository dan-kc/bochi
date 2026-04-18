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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            draftSelection = option
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.displayName)
                                        .font(.headline)
                                    Text(option.shortDescription)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                if draftSelection == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.fill.tertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    if let selected = draftSelection {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(selected.displayName)
                                .font(.title3.weight(.semibold))
                            Text(selected.shortDescription)
                                .foregroundStyle(.secondary)
                            Text("Example: \(selected.example)")
                                .font(.subheadline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.fill.tertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
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
        .presentationDetents([.medium, .large])
        .presentationBackground(.thinMaterial)
        .presentationContentInteraction(.scrolls)
    }
}
