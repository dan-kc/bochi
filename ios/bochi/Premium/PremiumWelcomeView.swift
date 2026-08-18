import SwiftUI

struct PremiumIncludedFeature: Identifiable {
    let title: String
    let systemImage: String
    let detail: String

    var id: String { title }
}

enum PremiumIncludedFeatureCatalog {
    static let all: [PremiumIncludedFeature] = [
        PremiumIncludedFeature(
            title: "Refunds",
            systemImage: "arrow.uturn.backward.circle",
            detail: "Undo mistaken task completions and reward purchases."
        ),
        PremiumIncludedFeature(
            title: "Advanced Sorting",
            systemImage: "arrow.up.arrow.down",
            detail: "Sort tasks, recurring tasks, and rewards with premium list controls."
        ),
        PremiumIncludedFeature(
            title: "Dependencies",
            systemImage: "link",
            detail: "Make tasks and rewards unlock after prerequisite work is done."
        ),
        PremiumIncludedFeature(
            title: "Reminders",
            systemImage: "bell",
            detail: "Add reminders to tasks and recurring tasks."
        ),
        PremiumIncludedFeature(
            title: "Lockouts",
            systemImage: "lock",
            detail: "Pace recurring tasks and rewards so they cannot repeat too soon."
        ),
        PremiumIncludedFeature(
            title: "Timers",
            systemImage: "timer",
            detail: "Use focused sessions, duration countdowns, and interval routines."
        ),
        PremiumIncludedFeature(
            title: "Adjustments",
            systemImage: "slider.horizontal.3",
            detail: "Fine-tune trades and prices when the normal ratios need a nudge."
        ),
        PremiumIncludedFeature(
            title: "Premium Themes",
            systemImage: "paintpalette",
            detail: "Switch between the full set of Bochi theme palettes."
        )
    ]
}

struct PremiumIncludedSection: View {
    @Environment(\.bochiTheme) private var theme

    var body: some View {
        Section("Included") {
            ForEach(PremiumIncludedFeatureCatalog.all) { feature in
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feature.title)
                        Text(feature.detail)
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText())
                    }
                } icon: {
                    Image(systemName: feature.systemImage)
                }
            }
        }
    }
}

struct PremiumWelcomeView: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumWelcomeStore.self) private var premiumWelcomeStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(theme.premiumFill())

                        Text("Welcome to Premium")
                            .font(.largeTitle.weight(.bold))

                        Text("Your premium features are ready.")
                            .foregroundStyle(theme.secondaryText())

                        if authManager.needsAccountToLinkPurchase {
                            Text("Sign in with Apple from Settings to sync this purchase across devices.")
                                .font(.footnote)
                                .foregroundStyle(theme.secondaryText())
                        }
                    }
                    .padding(.vertical, 8)
                }

                PremiumIncludedSection()
            }
            .scrollContentBackground(.hidden)
            .background(theme.appBackground())
            .foregroundStyle(theme.primaryText())
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        premiumWelcomeStore.dismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}
