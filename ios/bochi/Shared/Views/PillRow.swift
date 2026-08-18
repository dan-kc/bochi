import SwiftUI

enum PillRowTransitionStyle {
    case standard
    case entitySwitcher
}

// A horizontal row of tappable pill buttons — like a flexWrap row of chips
// or a horizontal ScrollView of filter buttons in React Native.
//
// Each pill can be "set" (selected neutral) or "unset" (normal neutral).
// Used for the form's action row: Tags, Difficulty, Frequency.
struct PillRow: View {
    let pills: [PillItem]
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0
    var transitionStyle: PillRowTransitionStyle = .standard

    private var animationSignature: [String] {
        pills.map { "\($0.id)|\($0.label)|\($0.icon)|\($0.isSet)|\($0.isPremiumLocked)|\($0.requiresAttention)" }
    }

    var body: some View {
        // ScrollView(.horizontal) is like overflow-x: auto with flex-direction: row.
        // showsIndicators: false hides the scroll bar.
        ScrollView(.horizontal, showsIndicators: false) {
            // HStack is a horizontal flex container — like flexDirection: "row".
            HStack(spacing: 8) {
                ForEach(pills) { pill in
                    PillButton(pill: pill)
                        .transition(transition(for: pill))
                        .zIndex(zIndex(for: pill))
                }
            }
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .animation(animation, value: animationSignature)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var animation: Animation? {
        switch transitionStyle {
        case .standard:
            return nil
        case .entitySwitcher:
            return .spring(response: 0.34, dampingFraction: 0.82)
        }
    }

    private func transition(for pill: PillItem) -> AnyTransition {
        switch transitionStyle {
        case .standard:
            return .identity
        case .entitySwitcher:
            let horizontalOffset = horizontalOffset(for: pill)
            return .asymmetric(
                insertion: .modifier(
                    active: PillTransitionModifier(
                        opacity: 0,
                        scale: 0.94,
                        xOffset: horizontalOffset,
                        yOffset: 0
                    ),
                    identity: PillTransitionModifier()
                )
                .animation(.easeOut(duration: 0.24).delay(0.2)),
                removal: .modifier(
                    active: PillTransitionModifier(
                        opacity: 0,
                        scale: 0.96,
                        xOffset: horizontalOffset * -0.65,
                        yOffset: 0
                    ),
                    identity: PillTransitionModifier()
                )
                .animation(.easeIn(duration: 0.16))
            )
        }
    }

    private func horizontalOffset(for pill: PillItem) -> CGFloat {
        switch pill.id {
        case "tags", "difficulty", "reminders", "duration":
            return -10
        default:
            return 14
        }
    }

    private func zIndex(for pill: PillItem) -> Double {
        switch pill.id {
        case "tags", "difficulty", "reminders", "duration":
            return 0
        default:
            return 1
        }
    }
}

struct LabeledPillRow: View {
    @Environment(\.bochiTheme) private var theme
    let title: String
    let pills: [PillItem]
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0
    var transitionStyle: PillRowTransitionStyle = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.secondaryText())
                .padding(.horizontal, leadingInset)

            PillRow(
                pills: pills,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                transitionStyle: transitionStyle
            )
        }
    }
}

private struct PillTransitionModifier: ViewModifier {
    var opacity: Double = 1
    var scale: CGFloat = 1
    var xOffset: CGFloat = 0
    var yOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(x: xOffset, y: yOffset)
    }
}

private struct PillButton: View {
    let pill: PillItem

    var body: some View {
        BochiControlPillButton(
            isSet: pill.isSet,
            isPremiumLocked: pill.isPremiumLocked,
            requiresAttention: pill.requiresAttention
        ) {
            pill.action?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: pill.icon)
                    .font(.callout.weight(.medium))

                pillLabel
            }
        }
    }

    @ViewBuilder
    private var pillLabel: some View {
        if pill.id == "price", pill.isSet {
            PointsAmountLabel(text: pill.label, iconSize: 13)
                .font(.callout)
        } else {
            Text(pill.label)
                .font(.callout)
        }
    }
}

struct BochiControlPillButton<Label: View>: View {
    @Environment(\.bochiTheme) private var theme
    let isSet: Bool
    var isPremiumLocked = false
    var requiresAttention = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    private var foregroundColor: Color {
        if requiresAttention {
            return BochiTheme.solidFill(palette: .red)
        }
        return isPremiumLocked ? theme.premiumText() : theme.primaryText()
    }

    private var backgroundColor: Color {
        if requiresAttention {
            return theme.componentBackground(for: .neutral)
        }
        return isPremiumLocked ? theme.premiumBackground() : theme.selectedBackground(for: .neutral)
    }

    private var borderColor: Color {
        if requiresAttention {
            return BochiTheme.solidFill(palette: .red)
        }
        return isPremiumLocked ? theme.premiumFill() : theme.strongBorder(for: .neutral)
    }

    var body: some View {
        Button(action: action) {
            label()
                .bochiControlPillSurface(
                    foregroundColor: foregroundColor,
                    backgroundColor: backgroundColor,
                    borderColor: borderColor,
                    showsBorder: isSet,
                    isFaded: !isSet
                )
                .contentTransition(.identity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}

// Represents a single pill in the row. Identifiable so ForEach can diff.
// `action` is optional so the same type works for both rendering (with action)
// and unit testing pill-building logic (without action). In React terms,
// this is like having an optional onClick prop on a button component.
struct PillItem: Identifiable {
    let id: String
    let label: String
    let icon: String          // SF Symbol name (like Material Icon names in React)
    let isSet: Bool           // true = selected, false = neutral
    var isPremiumLocked: Bool = false
    var requiresAttention: Bool = false
    var action: (() -> Void)? = nil  // called when tapped — like onClick in React
}
