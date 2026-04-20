import SwiftUI

// Shared row surface for habits and rewards. SwiftUI's built-in list separators
// do not let us both remove the final divider and tune the divider spacing, so
// we render the divider ourselves for each non-final row.
struct EntityListRowSurface<Content: View>: View {
    let showsDivider: Bool
    let content: Content

    init(
        showsDivider: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.showsDivider = showsDivider
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
    }
}
