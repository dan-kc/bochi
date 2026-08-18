import SwiftUI

// Shared horizontal scrolling treatment for compact pill rows.
//
// User behaviour protected here:
// when a row has more pills than fit, the user should be able to drag all the
// way back to the left edge while still getting the same trailing fade hint.
struct HorizontalFadeScrollRow<Content: View>: View {
    @Environment(\.bochiTheme) private var theme
    var leadingInset: CGFloat = 0
    var showsTrailingFade = false
    var trailingFadeInset: CGFloat = 0
    let content: Content

    private let fadeWidth: CGFloat = 24

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
                .padding(.leading, leadingInset)
                .padding(.trailing, showsTrailingFade ? (fadeWidth + trailingFadeInset) : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mask {
            if showsTrailingFade {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(
                        colors: [theme.primaryText(), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: fadeWidth)
                }
            } else {
                Rectangle()
            }
        }
    }
}
