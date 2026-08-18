import SwiftUI

// Shared row surface for tasks, recurringTasks, and rewards. SwiftUI's built-in list
// separators do not let us both remove the final divider and tune the divider
// spacing, so we render the divider ourselves for each non-final row.
struct EntityListRowSurface<Content: View>: View {
    @Environment(\.bochiTheme) private var theme
    private static var horizontalInset: CGFloat { 16 }
    private static var topContentInset: CGFloat { 14 }
    private static var bottomContentInset: CGFloat { 12 }

    let showsDivider: Bool
    let role: BochiThemeRole
    let isHighlighted: Bool
    let content: Content

    init(
        showsDivider: Bool,
        role: BochiThemeRole,
        isHighlighted: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.showsDivider = showsDivider
        self.role = role
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, Self.horizontalInset)
                .padding(.top, Self.topContentInset)

            if showsDivider {
                // Behaviour: keep extra air between the row content and the
                // divider so each recurringTask/reward reads as its own block, while
                // still preserving a crisp boundary before the next row.
                Rectangle()
                    .fill(dividerTint)
                    .frame(height: 1)
                    .mask(dividerFadeMask)
                    .padding(.top, 16)
                    .padding(.horizontal, Self.horizontalInset)
            } else {
                Color.clear
                    .frame(height: Self.bottomContentInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // Behaviour: native context menus snapshot the pressed row before they
        // animate it upward. Flattening the row into one surface stops SwiftUI
        // from lifting the trailing action pill separately from the text stack.
        .compositingGroup()
        .background {
            Rectangle()
                // Behaviour: a freshly created row briefly glows warm across
                // the full row so the destination stands out immediately.
                .fill(backgroundTint)
        }
    }

    private var backgroundTint: Color {
        if isHighlighted {
            return theme.selectedBackground(for: role).opacity(0.72)
        }

        return Color.clear
    }

    private var dividerTint: Color {
        theme.subtleBorder()
    }

    private var dividerFadeMask: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.88),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct EntityListRowActionColumn<Content: View>: View {
    let content: Content

    init(
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(minHeight: 34, alignment: .bottomTrailing)
        .fixedSize(horizontal: true, vertical: false)
        .frame(alignment: .bottomTrailing)
        .layoutPriority(1)
    }
}

enum EntityListRowStatus: String {
    case locked
    case hidden
    case completed

    var label: String {
        switch self {
        case .locked:
            "Locked"
        case .hidden:
            "Hidden"
        case .completed:
            "Completed"
        }
    }
}

struct EntityListRowStatusLabel: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(\.entityListColorStrategy) private var colorStrategy

    let status: EntityListRowStatus
    let role: BochiThemeRole

    var body: some View {
        Text(status.label)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(colorStrategy.secondaryText(for: role, theme: theme))
            .frame(minWidth: 86, minHeight: 34, alignment: .center)
    }
}

struct EntityListRowPriceDeltaLabel: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(\.entityListColorStrategy) private var colorStrategy

    let percent: Int?
    let role: BochiThemeRole

    var body: some View {
        if let label = PriceDeltaSupport.label(for: percent) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(colorStrategy.secondaryText(for: role, theme: theme))
                .accessibilityLabel("Price change \(label)")
        }
    }
}
