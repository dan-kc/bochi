import SwiftUI

// Shared row surface for habits and rewards. SwiftUI's built-in list separators
// do not let us both remove the final divider and tune the divider spacing, so
// we render the divider ourselves for each non-final row.
struct EntityListRowSurface<Content: View>: View {
    let showsDivider: Bool
    let isHighlighted: Bool
    let content: Content

    init(
        showsDivider: Bool,
        isHighlighted: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.showsDivider = showsDivider
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content

            if showsDivider {
                // Behaviour: keep extra air between the row content and the
                // divider so each habit/reward reads as its own block, while
                // still preserving a crisp boundary before the next row.
                Divider()
                    .padding(.top, 16)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                // Behaviour: a freshly created row briefly glows warm so the
                // user can immediately spot where the list scrolled them.
                .fill(Color.orange.opacity(isHighlighted ? 0.22 : 0))
        }
    }
}
