import SwiftUI

// Shared amount button for earn/spend actions. This keeps the list rows and
// edit sheets visually aligned without forcing recurringTasks and rewards into one
// generic feature model.
struct BochiActionButton: View {
    @Environment(\.bochiTheme) private var theme
    enum Layout {
        case compact
        case expanded(title: String)
    }

    let amount: Int
    let polarity: Polarity
    let layout: Layout
    var isEnabled: Bool = true
    var showsPremiumBadge: Bool = false
    var usesPremiumStyle: Bool = false
    var usesMainThemeStyle: Bool = false
    var themeRoleOverride: BochiThemeRole? = nil
    var compactForegroundOverride: Color? = nil
    var priceDeltaPercent: Int? = nil
    let action: () -> Void

    @State private var displayedAmount: Int?
    @State private var tintColor: Color?
    @State private var hasAppeared = false
    @State private var colorResetTask: Task<Void, Never>?

    enum Polarity {
        case earning
        case spending

        var prefix: String {
            switch self {
            case .earning:
                return "+"
            case .spending:
                return "-"
            }
        }

        var palette: BochiThemePaletteName {
            switch self {
            case .earning:
                return .green
            case .spending:
                return .red
            }
        }

        var tint: Color {
            BochiTheme.solidFill(palette: palette)
        }
    }

    var body: some View {
        Group {
            switch layout {
            case .compact:
                compactButton
            case .expanded(let title):
                expandedButton(title: title)
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            displayedAmount = amount
            tintColor = polarity.tint
            hasAppeared = true
        }
        .onChange(of: amount) { oldAmount, newAmount in
            guard oldAmount != newAmount else { return }

            guard hasAppeared else {
                displayedAmount = newAmount
                return
            }

            animateAmountChange(from: oldAmount, to: newAmount)
        }
        .onDisappear {
            colorResetTask?.cancel()
        }
    }

    @ViewBuilder
    private var compactButton: some View {
        if usesMainThemeStyle {
            BochiActionSurface(
                layout: .compactOnNeutral(foreground: theme.solidFill(for: .neutral)),
                isEnabled: isEnabled,
                action: action
            ) {
                compactLabel
            }
        } else if let compactForegroundOverride {
            BochiActionSurface(
                layout: .compactOnNeutral(foreground: compactForegroundOverride),
                isEnabled: isEnabled,
                action: action
            ) {
                compactLabel
            }
        } else if let themeRoleOverride {
            BochiActionSurface(
                layout: .compactEntityOnNeutral(themeRoleOverride),
                isEnabled: isEnabled,
                action: action
            ) {
                compactLabel
            }
        } else {
            BochiActionSurface(
                layout: .compact,
                isEnabled: isEnabled,
                action: action
            ) {
                compactLabel
            }
        }
    }

    private var compactLabel: some View {
        PointsAmountLabel(text: "\(polarity.prefix)\(displayAmount)", iconSize: 14)
            .lineLimit(1)
            .contentTransition(.numericText())
            .font(.callout)
            .fontWeight(.semibold)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func expandedButton(title: String) -> some View {
        if usesPremiumStyle {
            BochiActionSurface(
                layout: .expandedPremium,
                isEnabled: isEnabled,
                action: action
            ) {
                expandedLabel(title: title)
            }
        } else if usesMainThemeStyle {
            BochiActionSurface(
                layout: .expanded(tint: theme.solidFill(for: .neutral)),
                isEnabled: isEnabled,
                action: action
            ) {
                expandedLabel(title: title)
            }
        } else if let themeRoleOverride {
            BochiActionSurface(
                layout: .expandedEntity(themeRoleOverride),
                isEnabled: isEnabled,
                action: action
            ) {
                expandedLabel(title: title)
            }
        } else {
            BochiActionSurface(
                layout: .expanded(tint: tintColor ?? polarity.tint),
                isEnabled: isEnabled,
                action: action
            ) {
                expandedLabel(title: title)
            }
        }
    }

    private func expandedLabel(title: String) -> some View {
        HStack {
            Text(title)
            if showsPremiumBadge {
                PremiumFeatureBadge()
            }
            Spacer()
            HStack(spacing: 6) {
                PointsAmountLabel(text: "\(polarity.prefix)\(displayAmount)", iconSize: 14)
                    .contentTransition(.numericText())
                if let priceDeltaLabel {
                    Text(priceDeltaLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }

    private var displayAmount: Int {
        displayedAmount ?? amount
    }

    private var priceDeltaLabel: String? {
        PriceDeltaSupport.label(for: priceDeltaPercent)
    }

    private var accessibilityLabel: String {
        switch layout {
        case .compact:
            return "\(polarity.prefix)\(displayAmount)"
        case .expanded(let title):
            return title
        }
    }

    private func animateAmountChange(from oldAmount: Int, to newAmount: Int) {
        colorResetTask?.cancel()

        let flashColor = newAmount < oldAmount
            ? BochiTheme.solidFillHover(palette: polarity.palette)
            : BochiTheme.solidFill(palette: polarity.palette)

        withAnimation(.easeIn(duration: 0.2)) {
            tintColor = flashColor
        }

        withAnimation(.easeInOut(duration: 0.6)) {
            displayedAmount = newAmount
        }

        colorResetTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    tintColor = polarity.tint
                }
            }
        }
    }
}
