import SwiftUI

// Shared row surface for tasks, habits, and rewards. SwiftUI's built-in list
// separators do not let us both remove the final divider and tune the divider
// spacing, so we render the divider ourselves for each non-final row.
struct EntityListRowSurface<Content: View>: View {
    private static var horizontalInset: CGFloat { 16 }
    private static var verticalInset: CGFloat { 8 }

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
                .padding(.horizontal, Self.horizontalInset)
                .padding(.top, Self.verticalInset)

            if showsDivider {
                // Behaviour: keep extra air between the row content and the
                // divider so each habit/reward reads as its own block, while
                // still preserving a crisp boundary before the next row.
                Divider()
                    .padding(.top, 16)
                    .padding(.horizontal, Self.horizontalInset)
            } else {
                Color.clear
                    .frame(height: Self.verticalInset)
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
                .fill(Color.orange.opacity(isHighlighted ? 0.22 : 0))
        }
    }
}
